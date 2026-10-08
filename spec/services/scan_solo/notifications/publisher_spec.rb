# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Notifications::Publisher do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, stage: :negociacao,
                                          conversation: create(:conversation, account: account, contact: contact))
  end
  let(:payload) { { account_id: account.id, opportunity_id: opportunity.id, correlation_id: SecureRandom.uuid, stage: 'negociacao' } }
  let(:received) { [] }
  let(:recording_adapter) do
    calls = received
    Class.new do
      define_singleton_method(:name) { 'RecordingAdapter' }
      define_singleton_method(:call) do |event:, payload:|
        calls << [event, payload]
        ScanSolo::Notifications::Publisher::Result.new(success: true, reason: nil)
      end
    end
  end
  let(:raising_adapter) do
    Class.new do
      define_singleton_method(:name) { 'RaisingAdapter' }
      define_singleton_method(:call) { |**| raise 'smtp down' }
    end
  end
  let(:failing_adapter) do
    Class.new do
      define_singleton_method(:name) { 'FailingAdapter' }
      define_singleton_method(:call) { |**| ScanSolo::Notifications::Publisher::Result.new(success: false, reason: 'quote_inbox_missing') }
    end
  end

  before { allow(ChatwootExceptionTracker).to receive(:new).and_call_original }

  def publish(*adapters)
    described_class.call(event: 'negotiation.requested', payload: payload, adapters: adapters)
  end

  it 'uses the e-mail adapter by default (RF-41)' do
    expect(described_class::ADAPTERS).to eq([ScanSolo::Notifications::EmailAdapter])
  end

  it 'delivers the identical payload to the adapter and records the success' do
    publish(recording_adapter)

    expect(received).to eq([['negotiation.requested', payload]])
    expect(received.sole.last).to equal(payload)
    expect(ScanSolo::AuditEvent.where.not(event_type: described_class::CLAIM_EVENT).sole).to have_attributes(
      event_type: 'negotiation.notification_sent', subject: opportunity, correlation_id: payload[:correlation_id],
      payload: { 'adapter' => 'RecordingAdapter' }
    )
  end

  it 'records one failure and reports the exception of a raising adapter without propagating (RF-39)' do
    expect { publish(raising_adapter, recording_adapter) }.not_to raise_error

    expect(ScanSolo::AuditEvent.where(event_type: 'negotiation.notification_failed').sole)
      .to have_attributes(subject: opportunity, payload: { 'adapter' => 'RaisingAdapter', 'reason' => 'smtp down' })
    expect(ChatwootExceptionTracker).to have_received(:new).with(an_instance_of(RuntimeError), account: account).once
    expect(received.size).to eq(1)
  end

  it 'records a failed result with its reason' do
    expect { publish(failing_adapter) }.not_to raise_error

    expect(ScanSolo::AuditEvent.where.not(event_type: described_class::CLAIM_EVENT).sole)
      .to have_attributes(event_type: 'negotiation.notification_failed',
                          payload: { 'adapter' => 'FailingAdapter', 'reason' => 'quote_inbox_missing' })
    expect(ChatwootExceptionTracker).to have_received(:new)
      .with(an_instance_of(CustomExceptions::ScanSolo::NegotiationNotificationFailed), account: account).once
  end

  describe 'at most one publication per correlation_id (RF-23, RNF-02)' do
    it 'claims the correlation id once and skips a repeated call' do
      publish(recording_adapter)
      publish(recording_adapter)

      expect(received.size).to eq(1)
      expect(ScanSolo::AuditEvent.where(event_type: described_class::CLAIM_EVENT).sole)
        .to have_attributes(subject: opportunity, correlation_id: payload[:correlation_id])
    end

    it 'does not republish a correlation id whose adapter failed' do
      publish(raising_adapter)
      publish(recording_adapter)

      expect(received).to be_empty
    end

    context 'with the e-mail adapter' do
      let(:customer_inbox) { create(:inbox, account: account) }
      let(:email_inbox) do
        create(:channel_email, account: account, email: 'atendimento.comercial@scansolo.com.br', smtp_enabled: true,
                               smtp_address: 'smtp.example.com', smtp_port: 587, smtp_login: 'login', smtp_password: 'secret').inbox
      end
      let(:payload) do
        {
          account_id: account.id, opportunity_id: opportunity.id, conversation_id: opportunity.conversation_id,
          conversation_url: 'https://app.example.com/app/accounts/1/conversations/9',
          contact: { name: 'Ana Souza', company: 'Solar Ltda', phone: '+5511987654321' }, stage: 'negociacao',
          request_summary: 'Consegue 10% de desconto?', proposal: nil, current_value: nil, recent_messages: [],
          correlation_id: SecureRandom.uuid
        }
      end

      # RNF-04: 0 real SMTP (see spec/services/scan_solo/quote/email_thread_spec.rb).
      around do |example|
        original = ActionMailer::Base.delivery_method
        ActionMailer::Base.delivery_method = :test
        example.run
      ensure
        ActionMailer::Base.delivery_method = original
      end

      before do
        allow_any_instance_of(ConversationReplyMailer).to receive(:set_delivery_method) # rubocop:disable RSpec/AnyInstance
        ActionMailer::Base.deliveries.clear
        ScanSolo::AiAgentConfig.draft_for!(account).update!(name: 'Agente', enabled: true, allowed_inbox_ids: [customer_inbox.id],
                                                            quote_inbox_id: email_inbox.id)
        ScanSolo::AiAgent::PublishService.new(account: account).call
      end

      def publish_email(correlation_id)
        perform_enqueued_jobs(only: SendReplyJob) do
          described_class.call(event: 'negotiation.requested', payload: payload.merge(correlation_id: correlation_id))
        end
      end

      it 'sends 1 negotiation e-mail for 2 calls with the same correlation id' do
        2.times { publish_email(payload[:correlation_id]) }

        expect(email_inbox.messages.count).to eq(1)
        expect(ActionMailer::Base.deliveries.size).to eq(1)
      end

      it 'sends 2 negotiation e-mails for 2 different correlation ids' do
        publish_email(SecureRandom.uuid)
        publish_email(SecureRandom.uuid)

        expect(email_inbox.messages.count).to eq(2)
        expect(ActionMailer::Base.deliveries.size).to eq(2)
      end
    end
  end
end
