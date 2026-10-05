# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Negotiation::RequestService do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:email_inbox) { create(:channel_email, account: account, email: 'atendimento.comercial@scansolo.com.br').inbox }
  let(:commercial_user) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Ana Souza') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact,
                     content: 'Consegue 10% de desconto?')
  end
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :proposta_enviada)
  end
  let(:turn) { ScanSolo::AiTurn.create!(message: message, conversation: conversation, correlation_id: SecureRandom.uuid) }
  let(:extension) { ScanSolo::ConversationExtension.resolve_for(conversation) }
  let(:config_attributes) { { quote_inbox_id: email_inbox.id, quote_recipient_email: 'luciano@scansolo.com.br' } }

  before do
    allow(ChatwootExceptionTracker).to receive(:new).and_call_original
    ScanSolo::AiAgentConfig.draft_for!(account).update!(name: 'Agente', enabled: true, allowed_inbox_ids: [inbox.id], **config_attributes)
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  def call
    ActiveRecord::Base.transaction { described_class.call(opportunity: opportunity, turn: turn, message: message) }
  end

  def notifications
    Message.where(inbox: email_inbox, message_type: :outgoing)
  end

  it 'moves proposta_enviada to negociacao, hands off and notifies only after the commit (RF-35, RF-37)' do
    ActiveRecord::Base.transaction do
      described_class.call(opportunity: opportunity, turn: turn, message: message)
      expect(notifications.count).to eq(0)
    end

    expect(opportunity.reload).to be_negociacao
    expect(opportunity.stage_events.sole).to have_attributes(from_stage: 'proposta_enviada', to_stage: 'negociacao')
    expect(extension.reload).to be_awaiting_human
    expect(conversation.messages.where(private: true).sole.content).to include('Motivo da transferência: Pedido de negociação comercial')
    expect(notifications.sole.conversation.additional_attributes).to include('scansolo_thread' => 'negotiation_notification')
    expect(ScanSolo::AuditEvent.where(event_type: 'negotiation.notification_sent').count).to eq(1)
  end

  it 'audits the request with the turn correlation id' do
    call

    expect(ScanSolo::AuditEvent.find_by!(event_type: 'negotiation.requested'))
      .to have_attributes(subject: opportunity, correlation_id: turn.correlation_id,
                          payload: { 'from_stage' => 'proposta_enviada', 'message_id' => message.id })
  end

  it 'leaves no cadence attempt scheduled after the negotiation' do
    definition = ScanSolo::CadenceDefinition.create!(stage: 'proposta_enviada', version: 1, offsets: [24, 72])
    enrollment = ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: definition)

    call

    expect(enrollment.reload).not_to be_active
    expect(opportunity.cadence_enrollments.where(status: :active)).to be_none
    expect(ScanSolo::CadenceAttempt.where(enrollment: enrollment, result: 'scheduled')).to be_none
  end

  context 'when the opportunity is already in negociacao' do
    let(:opportunity) do
      ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :negociacao)
    end

    it 'hands off, pauses the cadence and notifies without a stage event (RF-35)' do
      definition = ScanSolo::CadenceDefinition.create!(stage: 'proposta_enviada', version: 1, offsets: [24, 72])
      enrollment = ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: definition)

      call

      expect(opportunity.reload).to be_negociacao
      expect(opportunity.stage_events).to be_none
      expect(extension.reload).to be_awaiting_human
      expect(enrollment.reload).to be_paused
      expect(notifications.count).to eq(1)
    end
  end

  describe 'commercial user assignment (RF-38)' do
    let(:config_attributes) { { quote_inbox_id: email_inbox.id, commercial_user_id: commercial_user.id } }

    it 'assigns the conversation to the commercial user who is an agent of the inbox' do
      create(:inbox_member, inbox: inbox, user: commercial_user)

      call

      expect(conversation.reload.assignee_id).to eq(commercial_user.id)
    end

    it 'keeps the assignee when the commercial user is not an agent of the inbox' do
      expect { call }.not_to(change { conversation.reload.assignee_id })
      expect(notifications.count).to eq(1)
    end

    it 'records the failure and keeps the negotiation when the assignment raises (RF-39)' do
      create(:inbox_member, inbox: inbox, user: commercial_user)
      allow_any_instance_of(Conversation).to receive(:update!).and_raise(ActiveRecord::RecordInvalid) # rubocop:disable RSpec/AnyInstance

      expect { call }.not_to raise_error

      expect(ScanSolo::AuditEvent.where(event_type: 'negotiation.assignment_failed').sole)
        .to have_attributes(subject: opportunity, payload: include('user_id' => commercial_user.id))
      expect(ChatwootExceptionTracker).to have_received(:new).with(an_instance_of(ActiveRecord::RecordInvalid), account: account).once
      expect(opportunity.reload).to be_negociacao
    end
  end

  it 'keeps the assignee unchanged and still notifies without a commercial user' do
    expect { call }.not_to(change { conversation.reload.assignee_id })
    expect(notifications.count).to eq(1)
  end

  context 'when the quote inbox is missing' do
    let(:config_attributes) { { quote_inbox_id: nil } }

    it 'keeps negociacao and the handoff, recording one failure and one exception (RF-39)' do
      expect { call }.not_to raise_error

      expect(opportunity.reload).to be_negociacao
      expect(extension.reload).to be_awaiting_human
      expect(ScanSolo::AuditEvent.where(event_type: 'negotiation.notification_failed').count).to eq(1)
      expect(ChatwootExceptionTracker).to have_received(:new)
        .with(an_instance_of(CustomExceptions::ScanSolo::NegotiationNotificationFailed), account: account).once
      expect(notifications).to be_none
    end
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
end
