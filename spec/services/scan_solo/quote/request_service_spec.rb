# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Quote::RequestService do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:customer_inbox) { create(:inbox, account: account) }
  let(:email_inbox) do
    create(:channel_email, account: account, email: 'atendimento.comercial@scansolo.com.br', smtp_enabled: true,
                           smtp_address: 'smtp.example.com', smtp_port: 587, smtp_login: 'login', smtp_password: 'secret').inbox
  end
  let(:contact) { create(:contact, account: account, name: 'Ana Souza') }
  let(:conversation) { create(:conversation, account: account, inbox: customer_inbox, contact: contact) }
  let(:opportunity) { ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado) }
  let(:message) { create(:message, account: account, conversation: conversation, message_type: :incoming) }
  let(:writer) { ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state) }
  let(:draft) { ScanSolo::AiAgentConfig.draft_for!(account) }
  let(:intent) { 'orcamento' }
  let(:notice_text) do
    'Recebi todas as informações, obrigado! Nosso comercial já está preparando seu orçamento. Assim que estiver pronto, envio por aqui.'
  end
  let(:notices) { conversation.messages.where("additional_attributes ->> 'scansolo_origin' = 'quote_notice'") }
  let(:quote_request) { ScanSolo::QuoteRequest.find_by!(opportunity: opportunity) }

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
    allow(ChatwootExceptionTracker).to receive(:new).and_call_original
    ActionMailer::Base.deliveries.clear
    draft.update!(name: 'Agente', enabled: true, allowed_inbox_ids: [customer_inbox.id], quote_inbox_id: email_inbox.id)
    ScanSolo::AiAgent::PublishService.new(account: account).call
    writer.complete!(at: Time.current)
    writer.set_intent!(intent: intent, source_message_id: message.id)
    writer.record_next_action!(value: ScanSolo::LeadState::DEFAULT_NEXT_ACTION_BY_INTENT.fetch(intent), source_message_id: message.id)
  end

  def run_service
    perform_enqueued_jobs(only: SendReplyJob) { described_class.call(opportunity: ScanSolo::PipelineOpportunity.find(opportunity.id)) }
  end

  def republish!(**attributes)
    draft.update!(attributes)
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  describe 'quote request (RF-12, RF-13, CT-03)' do
    it 'creates one request, one e-mail conversation and one e-mail to the published recipient' do
      expect { run_service }.to change(ScanSolo::QuoteRequest, :count).by(1).and change(email_inbox.conversations, :count).by(1)

      request_message = email_inbox.messages.sole
      expect(quote_request).to have_attributes(status: 'awaiting_reply', email_conversation_id: request_message.conversation_id,
                                               request_message_id: request_message.id, sent_at: be_present)
      expect(request_message.content_attributes['to_emails']).to eq(['comercial@scansolo.com.br'])
      expect(request_message.conversation.additional_attributes).to include('scansolo_thread' => 'quote_request')

      mail = ActionMailer::Base.deliveries.sole
      expect(mail).to have_attributes(from: ['atendimento.comercial@scansolo.com.br'], to: ['comercial@scansolo.com.br'],
                                      subject: "Solicitação de orçamento ##{opportunity.id} — Ana Souza")
    end

    it 'records quote_request.sent with the request correlation id (RF-22, RNF-09)' do
      run_service

      expect(ScanSolo::AuditEvent.where(event_type: 'quote_request.sent').sole)
        .to have_attributes(subject: opportunity, correlation_id: quote_request.correlation_id)
    end

    it 'sends to a new published recipient (RF-54)' do
      republish!(quote_recipient_email: 'luciano@scansolo.com.br')

      run_service

      expect(email_inbox.messages.sole.content_attributes['to_emails']).to eq(['luciano@scansolo.com.br'])
    end

    it 'keeps the published recipient while the new one is only in the draft (RF-54)' do
      draft.update!(quote_recipient_email: 'outro@scansolo.com.br')

      run_service

      expect(email_inbox.messages.sole.content_attributes['to_emails']).to eq(['comercial@scansolo.com.br'])
    end

    it 'delivers the e-mail and the notice only with no open transaction (RNF-01)' do
      transaction_open = []
      allow(SendReplyJob).to receive(:perform_later).and_wrap_original do |original, *args|
        transaction_open << ActiveRecord::Base.connection.current_transaction.joinable?
        original.call(*args)
      end

      run_service

      expect(transaction_open).to eq([false, false])
    end
  end

  %w[duvida avaliacao_tecnica localizar_rede].each do |other_intent|
    context "with intent #{other_intent}" do
      let(:intent) { other_intent }

      it 'requests nothing (RF-12)' do
        expect { run_service }.not_to change(ScanSolo::QuoteRequest, :count)
        expect(Message.where(inbox: email_inbox)).to be_empty
        expect(notices).to be_empty
      end
    end
  end

  it 'requests nothing while the qualification is still em_andamento' do
    other = ScanSolo::PipelineOpportunity.create!(account: account, contact: create(:contact, account: account),
                                                  conversation: create(:conversation, account: account, inbox: customer_inbox))
    ScanSolo::LeadState::Writer.new(lead_state: other.lead_state).record_next_action!(value: 'proposta', source_message_id: message.id)

    expect { described_class.call(opportunity: other) }.not_to change(ScanSolo::QuoteRequest, :count)
  end

  describe 'misconfigured quote inbox (RF-14)' do
    shared_examples 'a misconfigured request' do |reason|
      it "records #{reason}, reports once and sends nothing" do
        expect { run_service }.not_to change(ScanSolo::QuoteRequest, :count)

        expect(Message.where(inbox: email_inbox)).to be_empty
        expect(notices).to be_empty
        expect(ScanSolo::AuditEvent.where(event_type: 'quote_request.misconfigured').sole)
          .to have_attributes(subject: opportunity, payload: { 'reason' => reason })
        expect(ChatwootExceptionTracker).to have_received(:new)
          .with(an_instance_of(CustomExceptions::ScanSolo::QuoteInboxMisconfigured), account: account).once
        expect(opportunity.lead_state.reload).to be_concluida
      end
    end

    context 'without a quote inbox' do
      before { republish!(quote_inbox_id: nil) }

      it_behaves_like 'a misconfigured request', 'quote_inbox_missing'
    end

    context 'with a non e-mail quote inbox' do
      before { republish!(quote_inbox_id: customer_inbox.id) }

      it_behaves_like 'a misconfigured request', 'quote_inbox_not_email'
    end

    context 'with an allowlisted quote inbox' do
      before { republish!(allowed_inbox_ids: [customer_inbox.id, email_inbox.id]) }

      it_behaves_like 'a misconfigured request', 'quote_inbox_allowlisted'
    end
  end

  describe 'idempotency (RF-15, RNF-02)' do
    it 'sends one request and one e-mail for two concurrent jobs' do
      Array.new(2) { Thread.new { run_service } }.each(&:join)

      expect(ScanSolo::QuoteRequest.where(opportunity: opportunity).count).to eq(1)
      expect(email_inbox.messages.count).to eq(1)
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(notices.count).to eq(1)
    end

    it 'sends nothing again when the job runs a second time' do
      run_service

      expect { run_service }.not_to change(Message, :count)
      expect(ScanSolo::AuditEvent.where(event_type: 'quote_request.sent').count).to eq(1)
    end
  end

  describe 'customer notice (RF-53)' do
    it 'posts the exact notice once to the customer conversation, keeping the AI active' do
      run_service

      expect(notices.sole).to have_attributes(message_type: 'outgoing', content: notice_text)
      expect(quote_request.customer_notice_message_id).to eq(notices.sole.id)
      expect(ScanSolo::ConversationExtension.resolve_for(conversation)).to be_ai_active
    end

    it 'never repeats it on the two following turns or a repeated job' do
      run_service
      2.times do
        turn_message = create(:message, account: account, conversation: conversation, message_type: :incoming)
        turn = ScanSolo::AiTurn.create!(message: turn_message, conversation: conversation, correlation_id: SecureRandom.uuid)
        ScanSolo::LeadState::CompletionService.call(opportunity: opportunity, turn: turn)
      end
      run_service

      expect(notices.count).to eq(1)
      expect(ScanSolo::QuoteRequestJob).not_to have_been_enqueued
    end

    it 'posts the pending notice when the job resumes an already sent request' do
      run_service
      notices.sole.destroy!
      quote_request.update!(customer_notice_message_id: nil)

      expect { run_service }.not_to change(email_inbox.messages, :count)
      expect(notices.count).to eq(1)
    end

    it 'is not posted once the request left awaiting_reply' do
      run_service
      notices.sole.destroy!
      quote_request.update!(customer_notice_message_id: nil, status: :replied)

      run_service

      expect(notices).to be_empty
    end
  end
end
