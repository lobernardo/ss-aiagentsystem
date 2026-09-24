# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::ConversationListener do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:listener) { described_class.instance }

  before do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente ScanSolo', enabled: true, allowed_inbox_ids: [inbox.id])
    ScanSolo::AiAgent::PublishService.new(account: account).call
    ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2, 24, 48, 96])
    ScanSolo::CadenceDefinition.create!(stage: 'em_contato', version: 1, offsets: [24, 48, 72, 96, 120])
  end

  def incoming(content = 'Olá')
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact,
                     content: content)
  end

  def dispatch(message)
    listener.message_created(Events::Base.new('message_created', Time.zone.now, { message: message }))
  end

  it 'is registered on the AsyncDispatcher listener seam' do
    expect(AsyncDispatcher.new.listeners).to include(described_class.instance)
  end

  describe 'RF-01/RF-02: single eligibility gate before any write or enqueue' do
    {
      'account flag off' => -> { account.update!(scansolo_enabled: false) },
      'inbox not allowlisted' => lambda {
        ScanSolo::AiAgentConfig.draft_for!(account).update!(allowed_inbox_ids: [])
        ScanSolo::AiAgent::PublishService.new(account: account).call
      },
      'inbox with an active bot' => -> { create(:agent_bot_inbox, inbox: inbox, status: :active) }
    }.each do |condition, setup|
      it "creates 0 opportunities, 0 turns and 0 enqueues when the #{condition}" do
        message = incoming
        instance_exec(&setup)

        expect { dispatch(message) }.not_to have_enqueued_job(ScanSolo::AiTurnJob)
        expect(ScanSolo::PipelineOpportunity.count).to eq(0)
        expect(ScanSolo::AiTurn.count).to eq(0)
      end
    end

    it 'enqueues exactly one AI turn job when every condition holds' do
      message = incoming

      expect { dispatch(message) }.to have_enqueued_job(ScanSolo::AiTurnJob).with(message.id).exactly(:once)
    end
  end

  describe 'RF-22/RF-23: opportunity bootstrap and stage progression' do
    it 'keeps the creating message in novo_lead with a Novo Lead enrollment, and moves to em_contato on the next one' do
      first = incoming
      dispatch(first)

      opportunity = ScanSolo::PipelineOpportunity.find_by!(conversation_id: conversation.id)
      expect(opportunity).to be_novo_lead
      novo_lead_enrollment = opportunity.cadence_enrollments.active.sole
      expect(novo_lead_enrollment.cadence_definition.stage).to eq('novo_lead')

      second = incoming('Quero saber o preço')
      dispatch(second)

      expect(opportunity.reload).to be_em_contato
      expect(opportunity.last_customer_interaction_at).to be_within(1.second).of(second.created_at)
      expect(novo_lead_enrollment.reload).to be_cancelled
      expect(opportunity.cadence_enrollments.active.sole.cadence_definition.stage).to eq('em_contato')
    end
  end

  describe 'RF-16 (b): deterministic opt-out keyword' do
    it 'marks the contact and cancels its enrollments for PARAR' do
      dispatch(incoming('PARAR'))

      expect(ScanSolo::ContactExtension.opted_out?(contact)).to be true
      expect(ScanSolo::CadenceEnrollment.where(status: %i[active paused]).count).to eq(0)
    end

    it 'leaves the marker unchanged for a phrase that only contains a keyword' do
      dispatch(incoming('não vou parar agora'))

      expect(ScanSolo::ContactExtension.opted_out?(contact)).to be false
    end

    it 'keeps the marker after a later non-keyword message (no automatic reset)' do
      dispatch(incoming('Parar!'))
      dispatch(incoming('na verdade, quero o orçamento'))

      expect(ScanSolo::ContactExtension.opted_out?(contact)).to be true
    end

    it 'still enqueues the AI turn so the contact keeps getting replies (RF-31)' do
      message = incoming('SAIR')

      expect { dispatch(message) }.to have_enqueued_job(ScanSolo::AiTurnJob).with(message.id)
    end
  end

  describe 'RF-18: implicit takeover on a manual human reply' do
    def outgoing(**attrs)
      create(:message, { account: account, inbox: inbox, conversation: conversation, message_type: :outgoing }.merge(attrs))
    end

    it 'moves the conversation to human_active and records one handoff.takeover with trigger human_reply' do
      dispatch(outgoing(sender: agent, content: 'Oi, aqui é a Ana'))

      expect(ScanSolo::ConversationExtension.resolve_for(conversation)).to be_human_active
      event = ScanSolo::AuditEvent.find_by!(event_type: 'handoff.takeover')
      expect(event.actor).to eq(agent)
      expect(event.payload['trigger']).to eq('human_reply')
    end

    {
      'a private note' => -> { { sender: agent, private: true } },
      'an AI reply' => -> { { sender: create(:agent_bot, account: account), additional_attributes: { 'scansolo_origin' => 'ai' } } },
      'a cadence message' => -> { { sender: nil, additional_attributes: { 'scansolo_origin' => 'cadence' } } },
      'a proposal send by a user' => -> { { sender: agent, additional_attributes: { 'scansolo_origin' => 'proposal' } } }
    }.each do |kind, attrs|
      it "ignores #{kind}" do
        dispatch(outgoing(**instance_exec(&attrs)))

        expect(ScanSolo::ConversationExtension.resolve_for(conversation)).to be_ai_active
        expect(ScanSolo::AuditEvent.where(event_type: 'handoff.takeover')).to be_none
      end
    end

    it 'ignores a human reply on an ineligible inbox' do
      ScanSolo::AiAgentConfig.draft_for!(account).update!(allowed_inbox_ids: [])
      ScanSolo::AiAgent::PublishService.new(account: account).call

      dispatch(outgoing(sender: agent))

      expect(ScanSolo::AuditEvent.where(event_type: 'handoff.takeover')).to be_none
    end
  end
end
