# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Negotiation::RequestService do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:email_inbox) { create(:channel_email, account: account, email: 'atendimento.comercial@scansolo.com.br').inbox }
  let(:assignee) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Ana Souza') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, assignee: assignee) }
  let(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact,
                     content: 'Consegue 10% de desconto?')
  end
  let(:stage) { :proposta_enviada }
  let(:opportunity) { ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: stage) }
  let(:turn) { ScanSolo::AiTurn.create!(message: message, conversation: conversation, correlation_id: SecureRandom.uuid) }
  let(:extension) { ScanSolo::ConversationExtension.resolve_for(conversation) }
  let(:config_attributes) do
    { quote_inbox_id: email_inbox.id, quote_recipient_email: 'comercial@scansolo.com.br', commercial_whatsapp_number: '+5511999999999' }
  end
  let(:escalation_reason) { 'negociacao' }

  before do
    allow(ChatwootExceptionTracker).to receive(:new).and_call_original
    allow(ScanSolo::Cadence::StopRecalculatePolicy).to receive(:call).and_call_original
    ScanSolo::AiAgentConfig.draft_for!(account).update!(name: 'Agente', enabled: true, allowed_inbox_ids: [inbox.id], **config_attributes)
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  def call
    ActiveRecord::Base.transaction do
      described_class.call(opportunity: opportunity, turn: turn, message: message, escalation_reason: escalation_reason)
    end
  end

  def notifications
    Message.where(inbox: email_inbox, message_type: :outgoing)
  end

  def events(event_type)
    ScanSolo::AuditEvent.where(event_type: event_type)
  end

  def mark_escalated!
    opportunity.update_columns(escalated_to_commercial_at: 2.days.ago, escalation_reason: 'pedido_humano') # rubocop:disable Rails/SkipsModelValidations
  end

  context 'when in proposta_enviada and not escalated before' do
    it 'moves to negociacao, marks the escalation and notifies once only after the commit (RF-13, RF-23)' do
      ActiveRecord::Base.transaction do
        described_class.call(opportunity: opportunity, turn: turn, message: message, escalation_reason: escalation_reason)
        expect(notifications.count).to eq(0)
      end

      expect(opportunity.reload).to be_negociacao
      expect(opportunity.stage_events.sole).to have_attributes(from_stage: 'proposta_enviada', to_stage: 'negociacao')
      expect(opportunity).to have_attributes(escalation_reason: 'negociacao', escalated_to_commercial_at: be_present)
      expect(events('commercial.escalated').count).to eq(1)
      expect([events('negotiation.requested').count, events('negotiation.notification_sent').count, notifications.count]).to eq([1, 1, 1])
    end

    it 'keeps the AI active, the assignee unchanged, and creates no private note or handoff cadence stop (RF-13)' do
      expect { call }.not_to(change { conversation.reload.assignee_id })

      expect(extension.reload).to be_ai_active
      expect(conversation.messages.where(private: true)).to be_none
      expect(ScanSolo::Cadence::StopRecalculatePolicy).not_to have_received(:call).with(hash_including(trigger: 'handoff'))
    end

    it 'audits the request with the turn correlation id and the escalation reason' do
      call

      expect(events('negotiation.requested').sole)
        .to have_attributes(subject: opportunity, correlation_id: turn.correlation_id,
                            payload: { 'from_stage' => 'proposta_enviada', 'message_id' => message.id, 'escalation_reason' => 'negociacao' })
    end
  end

  context 'when already escalated in negociacao' do
    let(:stage) { :negociacao }

    it 'overwrites the mark and records 1 new escalation, without a stage event or a new notice e-mail (RF-14, RF-23)' do
      mark_escalated!
      previous_at = opportunity.reload.escalated_to_commercial_at

      no_notice = not_change { events('negotiation.notification_sent').count }.and(not_change { notifications.count })

      expect { call }.to change { events('commercial.escalated').count }.by(1).and(no_notice)

      expect(opportunity.reload).to have_attributes(escalation_reason: 'negociacao', stage: 'negociacao')
      expect(opportunity.escalated_to_commercial_at).to be > previous_at
      expect(opportunity.stage_events).to be_none
      expect(extension.reload).to be_ai_active
    end
  end

  context 'when in qualificado with duvida_proposta' do
    let(:stage) { :qualificado }
    let(:escalation_reason) { 'duvida_proposta' }

    it 'keeps the stage, marks the escalation and notifies once when not escalated before (RF-14)' do
      call

      expect(opportunity.reload).to be_qualificado
      expect(opportunity.stage_events).to be_none
      expect(opportunity.escalation_reason).to eq('duvida_proposta')
      expect(events('negotiation.requested').count).to eq(1)
      expect(events('negotiation.notification_sent').count).to eq(1)
    end

    it 'records 1 new escalation and no new notice when already escalated' do
      mark_escalated!

      expect { call }.to change { events('commercial.escalated').count }.by(1).and(not_change { events('negotiation.notification_sent').count })

      expect(opportunity.reload).to have_attributes(stage: 'qualificado', escalation_reason: 'duvida_proposta')
    end
  end

  context 'without an escalation reason (no published number, RF-19)' do
    let(:config_attributes) { { quote_inbox_id: email_inbox.id, quote_recipient_email: 'comercial@scansolo.com.br' } }
    let(:escalation_reason) { nil }

    it 'writes no mark and publishes the negotiation e-mail once, as before' do
      call

      expect(opportunity.reload).to be_negociacao
      expect(opportunity.escalated_to_commercial_at).to be_nil
      expect(events('commercial.escalated')).to be_none
      expect(events('negotiation.notification_sent').count).to eq(1)
      expect(notifications.sole.conversation.additional_attributes).to include('scansolo_thread' => 'negotiation_notification')
      expect(extension.reload).to be_ai_active
    end

    it 'hands the identical CT-07 payload to a replacement adapter (RF-41)' do
      received = []
      adapter = Class.new do
        define_singleton_method(:name) { 'RecordingAdapter' }
        define_singleton_method(:call) do |event:, payload:|
          received << [event, payload]
          ScanSolo::Notifications::Publisher::Result.new(success: true, reason: nil)
        end
      end
      stub_const('ScanSolo::Notifications::Publisher::ADAPTERS', [adapter])

      call

      expected = ScanSolo::Notifications::NegotiationPayload.build(opportunity: opportunity.reload, trigger_message: message,
                                                                   correlation_id: turn.correlation_id)
      expect(received).to eq([['negotiation.requested', expected]])
      expect(notifications).to be_none
    end

    context 'when the quote inbox is missing' do
      let(:config_attributes) { { quote_inbox_id: nil } }

      it 'keeps negociacao, recording one failure and one exception (RF-39)' do
        expect { call }.not_to raise_error

        expect(opportunity.reload).to be_negociacao
        expect(events('negotiation.notification_failed').count).to eq(1)
        expect(ChatwootExceptionTracker).to have_received(:new)
          .with(an_instance_of(CustomExceptions::ScanSolo::NegotiationNotificationFailed), account: account).once
        expect(notifications).to be_none
      end
    end
  end
end
