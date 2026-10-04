# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ScanSolo quote request resend API (CT-12, RF-56)', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:customer_inbox) { create(:inbox, account: account) }
  let(:email_inbox) do
    create(:channel_email, account: account, email: 'atendimento.comercial@scansolo.com.br', smtp_enabled: true,
                           smtp_address: 'smtp.example.com', smtp_port: 587, smtp_login: 'login', smtp_password: 'secret').inbox
  end
  let(:contact) { create(:contact, account: account, name: 'Ana Souza') }
  let(:conversation) { create(:conversation, account: account, inbox: customer_inbox, contact: contact) }
  let(:opportunity) { ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado) }
  let(:draft) { ScanSolo::AiAgentConfig.draft_for!(account) }
  let(:path) { "/api/v1/accounts/#{account.id}/scan_solo/pipeline_opportunities/#{opportunity.id}/quote_request/resend" }
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
    republish!(name: 'Agente', enabled: true, allowed_inbox_ids: [customer_inbox.id], quote_inbox_id: email_inbox.id)
    writer = ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state)
    writer.complete!(at: Time.current)
    writer.record_next_action!(value: 'proposta', source_message_id: nil)
  end

  def republish!(**attributes)
    draft.update!(attributes)
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  def request_quote
    perform_enqueued_jobs(only: SendReplyJob) { ScanSolo::Quote::RequestService.call(opportunity: opportunity) }
  end

  def resend(user = admin)
    perform_enqueued_jobs(only: SendReplyJob) { post path, headers: user.create_new_auth_token, as: :json }
  end

  context 'with a request awaiting the reply' do
    before { request_quote }

    it 'posts one new e-mail in the same conversation, keeping the request and correlation id' do
      correlation_id = quote_request.correlation_id

      thread_messages = quote_request.email_conversation.messages.outgoing
      expect { resend }.to change(thread_messages, :count).by(1).and not_change(ScanSolo::QuoteRequest, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        'quote_request_id' => quote_request.id, 'status' => 'awaiting_reply', 'correlation_id' => correlation_id,
        'recipient' => 'comercial@scansolo.com.br', 'resent_at' => be_present
      )
      expect(quote_request.reload).to have_attributes(status: 'awaiting_reply', correlation_id: correlation_id)
      expect(ScanSolo::AuditEvent.where(event_type: 'quote_request.resent').sole).to have_attributes(
        actor: admin, subject: opportunity, correlation_id: correlation_id,
        payload: include('recipient' => 'comercial@scansolo.com.br', 'quote_request_id' => quote_request.id)
      )
      expect(notices.count).to eq(1)
    end

    it 'sends to the recipient published at resend time' do
      republish!(quote_recipient_email: 'luciano@scansolo.com.br')

      resend

      expect(quote_request.email_conversation.messages.outgoing.order(:id).last.content_attributes['to_emails'])
        .to eq(['luciano@scansolo.com.br'])
      expect(response.parsed_body['recipient']).to eq('luciano@scansolo.com.br')
    end
  end

  it 'creates the single request, one e-mail and one notice once the misconfigured inbox is fixed' do
    republish!(quote_inbox_id: nil)
    request_quote
    expect(ScanSolo::AuditEvent.where(event_type: 'quote_request.misconfigured').count).to eq(1)
    republish!(quote_inbox_id: email_inbox.id)

    expect { resend }.to change(ScanSolo::QuoteRequest, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(email_inbox.messages.outgoing.count).to eq(1)
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(notices.count).to eq(1)
  end

  it 'refuses a replied request with 0 messages' do
    request_quote
    quote_request.update!(status: :replied)

    expect { resend }.not_to change(Message, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'quote_request_closed')
  end

  it 'refuses an opportunity concluded before the deploy, with no request nor failure audit' do
    expect { resend }.not_to change(ScanSolo::QuoteRequest, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'quote_request_not_eligible')
  end

  it 'refuses a still invalid config with the RF-14 audit and exception' do
    republish!(quote_inbox_id: customer_inbox.id)

    expect { resend }.not_to change(Message, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'quote_inbox_misconfigured')
    expect(ScanSolo::AuditEvent.where(event_type: 'quote_request.misconfigured').sole.payload).to eq('reason' => 'quote_inbox_not_email')
    expect(ChatwootExceptionTracker).to have_received(:new)
      .with(an_instance_of(CustomExceptions::ScanSolo::QuoteInboxMisconfigured), account: account).once
  end

  it 'forbids a non administrator agent' do
    request_quote

    expect { resend(agent) }.not_to change(Message, :count)

    expect(response).to have_http_status(:forbidden)
  end

  it 'returns 404 with the ScanSolo flag off' do
    account.update!(scansolo_enabled: false)

    resend

    expect(response).to have_http_status(:not_found)
  end

  it 'exposes quote_request_resend_available on show (CT-02)' do
    show_path = "/api/v1/accounts/#{account.id}/scan_solo/pipeline_opportunities/#{opportunity.id}"
    get show_path, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['quote_request_resend_available']).to be(false)

    request_quote
    get show_path, headers: agent.create_new_auth_token, as: :json
    expect(response.parsed_body['quote_request_resend_available']).to be(true)
  end
end
