# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ScanSolo pending quote replies API (CT-08)', type: :request do
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
  let(:quote_request) { ScanSolo::QuoteRequest.find_by!(opportunity: opportunity) }
  let(:luciano) { create(:contact, account: account, email: 'luciano@scansolo.com.br') }
  let(:loose_conversation) do
    create(:conversation, account: account, inbox: email_inbox, contact: luciano,
                          additional_attributes: { 'mail_subject' => 'Orçamento Ana Souza' })
  end
  let(:base_path) { "/api/v1/accounts/#{account.id}/scan_solo/quote_replies" }
  let(:valid_block) do
    <<~TEXT
      === RESPOSTA DO ORÇAMENTO ===
      Valor total: R$ 12.500,00
      Prazo/cronograma: 30 dias
      Escopo/atividades: Sondagem SPT
      Condições de pagamento: 50% na assinatura
      Observações comerciais:
      === FIM ===
    TEXT
  end
  let(:block_without_payment) { valid_block.sub("Condições de pagamento: 50% na assinatura\n", '') }

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
    scenario_url = 'https://hook.make.example/scenario-webhook'
    allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :scenario_url).and_return(scenario_url)
    allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :secret).and_return('make-outbound-secret')
    allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :inbound_signing_secret).and_return('make-inbound-secret')
    stub_request(:post, scenario_url).to_return(status: 200, body: '{}')

    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente', enabled: true, allowed_inbox_ids: [customer_inbox.id], quote_inbox_id: email_inbox.id,
                  required_qualification_fields: [])
    ScanSolo::AiAgent::PublishService.new(account: account).call
    writer = ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state)
    writer.complete!(at: Time.current)
    writer.record_next_action!(value: 'proposta', source_message_id: nil)
    perform_enqueued_jobs(only: SendReplyJob) { ScanSolo::Quote::RequestService.call(opportunity: opportunity) }
  end

  def incoming_reply(content, in_conversation:)
    message = create(:message, account: account, inbox: email_inbox, conversation: in_conversation, message_type: :incoming,
                               sender: in_conversation.contact, content: content)
    ScanSolo::Quote::ReplyProcessor.call(message: message)
    ScanSolo::QuoteReply.find_by(message: message)
  end

  def unmatched(content = valid_block)
    incoming_reply(content, in_conversation: loose_conversation)
  end

  def late_reply
    incoming_reply(valid_block, in_conversation: quote_request.email_conversation)
    incoming_reply(valid_block, in_conversation: quote_request.email_conversation)
  end

  def list(user = admin)
    get base_path, params: { status: 'pending' }, headers: user.create_new_auth_token
  end

  def link(quote_reply, quote_request_id = quote_request.id, user = admin)
    perform_enqueued_jobs(only: SendReplyJob) do
      post "#{base_path}/#{quote_reply.id}/link", params: { quote_request_id: quote_request_id }, headers: user.create_new_auth_token, as: :json
    end
  end

  def discard(quote_reply, user = admin)
    post "#{base_path}/#{quote_reply.id}/discard", headers: user.create_new_auth_token, as: :json
  end

  describe 'GET index' do
    it 'lists the unmatched and late_reply pendings with the CT-08 fields' do
      loose = unmatched
      late = late_reply

      list

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to contain_exactly(
        {
          'id' => loose.id, 'conversation_id' => loose_conversation.id, 'message_id' => loose.message_id,
          'sender_email' => 'luciano@scansolo.com.br', 'subject' => 'Orçamento Ana Souza', 'received_at' => be_present,
          'excerpt' => valid_block.first(200), 'kind' => 'unmatched', 'quote_request_id' => nil
        },
        include('id' => late.id, 'conversation_id' => quote_request.email_conversation_id, 'kind' => 'late_reply',
                'quote_request_id' => quote_request.id)
      )
    end

    it 'refuses a status other than pending' do
      get base_path, params: { status: 'linked' }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'allows an agent member of the quote inbox' do
      create(:inbox_member, user: agent, inbox: email_inbox)
      unmatched

      list(agent)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.size).to eq(1)
    end

    it 'forbids an agent without access to the quote inbox' do
      list(agent)

      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 404 with the ScanSolo flag off' do
      account.update!(scansolo_enabled: false)

      list

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST link (RF-20)' do
    it 'reads a valid block as the request reply, generating one version and auditing the actor' do
      quote_reply = unmatched

      link(quote_reply)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('quote_request_id' => quote_request.id, 'status' => 'replied')
      expect(quote_request.reload).to have_attributes(status: 'replied', reply_message_id: quote_reply.message_id)
      expect(ScanSolo::ProposalVersion.where(quote_request: quote_request).count).to eq(1)
      expect(quote_reply.reload).to have_attributes(status: 'linked', quote_request_id: quote_request.id, resolved_by: admin, resolved_at: be_present)
      expect(ScanSolo::AuditEvent.find_by!(event_type: 'quote_reply.linked'))
        .to have_attributes(actor: admin, subject: opportunity, correlation_id: quote_request.correlation_id)

      list
      expect(response.parsed_body).to be_empty
    end

    it 'asks for the correction in the request thread for an invalid block' do
      quote_reply = unmatched(block_without_payment)

      expect { link(quote_reply) }.not_to change(loose_conversation.messages.outgoing, :count)

      expect(response.parsed_body).to eq('quote_request_id' => quote_request.id, 'status' => 'correction_requested')
      expect(ScanSolo::ProposalVersion.count).to eq(0)
      correction = quote_request.email_conversation.messages.outgoing.order(:id).last
      expect(correction.id).not_to eq(quote_request.request_message_id)
      expect(correction.content).to include('Condições de pagamento')
    end

    it 'refuses linking the same pending twice' do
      quote_reply = unmatched
      link(quote_reply)

      expect { link(quote_reply) }.not_to change(ScanSolo::ProposalVersion, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'already_linked')
    end

    it 'refuses linking a late_reply' do
      link(late_reply)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'quote_request_closed')
    end

    it 'refuses linking to a replied request' do
      quote_reply = unmatched
      quote_request.update!(status: :replied)

      link(quote_reply)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'quote_request_closed')
      expect(quote_reply.reload).to be_pending
    end

    it 'refuses a non integer quote_request_id' do
      link(unmatched, 'abc')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'invalid_quote_request_id')
    end

    it 'forbids an agent without access to the quote inbox' do
      link(unmatched, quote_request.id, agent)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'POST discard (RF-23)' do
    it 'discards a late_reply with one audit and no version' do
      quote_reply = late_reply

      expect { discard(quote_reply) }.not_to change(ScanSolo::ProposalVersion, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('id' => quote_reply.id, 'status' => 'discarded')
      expect(ScanSolo::AuditEvent.where(event_type: 'quote_reply.discarded').sole)
        .to have_attributes(actor: admin, correlation_id: quote_request.correlation_id)
      expect(quote_request.reload).to be_replied

      list
      expect(response.parsed_body).to be_empty
    end

    it 'refuses a repeated discard' do
      quote_reply = late_reply
      discard(quote_reply)

      discard(quote_reply)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'already_discarded')
    end

    it 'refuses discarding an unmatched pending' do
      discard(unmatched)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'not_discardable')
    end
  end
end
