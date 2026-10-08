# frozen_string_literal: true

require 'rails_helper'

# scansolo-operacao-centralizada T33: end-to-end proof of the centralized
# commercial operation (RF-11, RF-22, RF-34, RF-55 Etapa 1, RF-56, RNF-01,
# RNF-02, RNF-04, RNF-09). Real ScanSolo services are wired together; only the
# true external boundaries are replaced: the LLM (MockLlmProvider), Make
# (scenario webhook stubbed by WebMock, callback signed with a test secret),
# the WhatsApp transport (360dialog stubbed by WebMock) and SMTP (ActionMailer
# `:test`). Native events reach ScanSolo::ConversationListener the way
# EventDispatcherJob delivers them, called here explicitly.
#
# scansolo-proposta-aprovacao-email T32 / RNF-10: scenario (b) no longer
# delivers the PDF over WhatsApp right after the callback -- the callback
# leaves the version `awaiting_approval` (RF-01), the approval sends it to the
# lead by e-mail (RF-11) and `sent`/`proposta_enviada` follow the e-mail's
# `source_id` (RF-13), with the short WhatsApp notice afterwards.
RSpec.describe 'ScanSolo operação centralizada ponta a ponta', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:luciano) { create(:user, account: account, role: :agent) }
  let(:message_templates) do
    [
      { 'name' => 'scansolo_lead_manual_inicial', 'status' => 'APPROVED', 'language' => 'pt_BR', 'category' => 'UTILITY',
        'components' => [{ 'type' => 'BODY', 'text' => 'Olá {{1}}, aqui é da ScanSolo.' }] },
      { 'name' => 'scansolo_proposal_send', 'status' => 'APPROVED', 'language' => 'pt_BR', 'category' => 'UTILITY',
        'components' => [{ 'type' => 'HEADER', 'format' => 'DOCUMENT' }, { 'type' => 'BODY', 'text' => 'Segue a sua proposta.' }] },
      { 'name' => 'scansolo_proposta_aviso_email', 'status' => 'APPROVED', 'language' => 'pt_BR', 'category' => 'UTILITY',
        'components' => [{ 'type' => 'BODY', 'text' => 'Enviamos a sua proposta para o seu e-mail.' }] },
      { 'name' => 'scansolo_proposta_acompanhamento', 'status' => 'APPROVED', 'language' => 'pt_BR', 'category' => 'UTILITY',
        'components' => [{ 'type' => 'BODY', 'text' => 'Conseguiu ver a proposta?' }] }
    ]
  end
  let(:whatsapp_inbox) { create(:channel_whatsapp, account: account, sync_templates: false, message_templates: message_templates).inbox }
  let(:email_inbox) do
    create(:channel_email, account: account, email: 'atendimento.comercial@scansolo.com.br', smtp_enabled: true,
                           smtp_address: 'smtp.example.com', smtp_port: 587, smtp_login: 'login', smtp_password: 'secret').inbox
  end
  let(:draft) { ScanSolo::AiAgentConfig.draft_for!(account) }
  let(:listener) { ScanSolo::ConversationListener.instance }
  let(:scenario_url) { 'https://hook.make.example/scenario-webhook' }
  let(:artifact_url) { 'https://make.example/proposals/ana.pdf' }
  let(:transaction_open_at) { [] }
  let(:valid_block) do
    <<~TEXT
      Segue o orçamento.

      === RESPOSTA DO ORÇAMENTO ===
      Valor total: R$ 12.500,00
      Prazo/cronograma: 30 dias
      Escopo/atividades: Sondagem SPT
      Condições de pagamento: 50% na assinatura
      Observações comerciais:
      === FIM ===

      Em 01/10/2026 10:00, Atendimento escreveu:
      > #{ScanSolo::Quote::EmailComposer.empty_block.gsub("\n", "\n> ")}
    TEXT
  end
  let(:block_without_payment) { valid_block.sub("Condições de pagamento: 50% na assinatura\n", '') }

  # RNF-04: ActionMailer `:test`; the channel's SMTP switch is neutralized.
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
    allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :scenario_url).and_return(scenario_url)
    allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :secret).and_return('make-outbound-secret')
    allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :inbound_signing_secret).and_return('make-inbound-secret')
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('make.example').and_return(['93.184.216.34'])
    allow(ScanSolo::Proposal::ApproveService).to receive(:call).and_call_original
    allow(ScanSolo::Proposal::SendService).to receive(:call).and_call_original

    stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
    stub_request(:post, 'https://waba.360dialog.io/v1/messages').to_return do
      { status: 200, body: { messages: [{ id: "wamid.#{SecureRandom.hex(6)}" }] }.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
    stub_request(:post, scenario_url).to_return do
      transaction_open_at << [:make, ActiveRecord::Base.connection.current_transaction.joinable?]
      { status: 200, body: '{}' }
    end
    stub_request(:get, artifact_url).to_return do
      transaction_open_at << [:download, ActiveRecord::Base.connection.current_transaction.joinable?]
      { status: 200, body: '%PDF-1.4 proposta', headers: { 'Content-Type' => 'application/pdf' } }
    end

    create(:inbox_member, user: luciano, inbox: whatsapp_inbox)
    ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2, 24, 48, 96])
    ScanSolo::CadenceDefinition.create!(stage: 'proposta_enviada', version: 1, offsets: [24, 72])
    ScanSolo::TemplateMapping.create!(account: account, stage: 'lead_manual_inicial', step: nil, template_name: 'scansolo_lead_manual_inicial',
                                      language: 'pt_BR', params: [{ 'source' => 'contact_first_name' }])
    publish!(name: 'Agente ScanSolo', enabled: true, allowed_inbox_ids: [whatsapp_inbox.id], required_qualification_fields: ['Área'],
             require_proposal_approval: true, quote_inbox_id: email_inbox.id, commercial_user_id: luciano.id)
  end

  def publish!(**attributes)
    draft.update!(attributes)
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  # Every native transport job (WhatsApp and e-mail) and every ScanSolo job
  # enqueued inside the block runs, as Sidekiq would.
  def run_jobs(&)
    perform_enqueued_jobs(only: [SendReplyJob, ScanSolo::QuoteRequestJob, ScanSolo::QuoteReplyJob, ScanSolo::ProposalApprovalRequestJob,
                                 ScanSolo::ProposalDeliveryJob], &)
  end

  def customer_says(opportunity, content)
    message = create(:message, account: account, inbox: whatsapp_inbox, conversation: opportunity.conversation, message_type: :incoming,
                               sender: opportunity.contact, content: content)
    listener.message_created(Events::Base.new('message_created', Time.zone.now, { message: message }))
    message
  end

  def run_turn(message, actions)
    provider = ->(**kwargs) { ScanSolo::TestMode::MockLlmProvider.call(**kwargs, fixture_actions: actions) }
    run_jobs { ScanSolo::AiTurn::TurnOrchestrator.call(message: message, llm_provider: provider) }
    ScanSolo::AiTurn.find_by!(message_id: message.id)
  end

  def luciano_replies(email_conversation, content)
    message = create(:message, account: account, inbox: email_inbox, conversation: email_conversation, message_type: :incoming,
                               sender: email_conversation.contact, content: content)
    run_jobs { listener.message_created(Events::Base.new('message_created', Time.zone.now, { message: message })) }
    message
  end

  def post_signed_callback(version)
    body = {
      correlation_id: version.generate_correlation_id, idempotency_key: version.generate_correlation_id, action: 'proposal.generate',
      status: 'success',
      result: { proposal_version_id: version.id, artifact_url: artifact_url, total_value: 12_500.0, currency: 'BRL',
                valid_until: '2026-11-04T00:00:00Z' }
    }.to_json
    run_jobs do
      post '/webhooks/scan_solo/make', params: body,
                                       headers: { 'CONTENT_TYPE' => 'application/json',
                                                  'X-Make-Signature' => OpenSSL::HMAC.hexdigest('SHA256', 'make-inbound-secret', body) }
    end
  end

  # (a) CT-01 → initial template → customer reply → em_contato (RF-11) →
  # qualifying turn concluding with next action `proposta`.
  def create_manual_lead!
    run_jobs do
      post "/api/v1/accounts/#{account.id}/scan_solo/pipeline_opportunities",
           params: { name: 'Ana Souza', phone_number: '+5511987654321', company: 'Solar Ltda', inbox_id: whatsapp_inbox.id },
           headers: admin.create_new_auth_token, as: :json
    end
    expect(response).to have_http_status(:created)
    ScanSolo::PipelineOpportunity.find(response.parsed_body['id'])
  end

  def qualify_manual_lead!
    opportunity = create_manual_lead!
    message = customer_says(opportunity, 'Oi! Quero um orçamento de sondagem para 800 m²')
    expect(opportunity.reload).to be_em_contato
    expect(ScanSolo::AiTurnJob).to have_been_enqueued.with(message.id)

    turn = run_turn(message, [{ 'action_id' => 'lead_state_update', 'params' => { 'intent' => 'orcamento' } },
                              { 'action_id' => 'qualification_field', 'params' => { 'fields' => { 'area' => '800 m²' } } }])
    expect(turn).to be_succeeded
    opportunity.reload
  end

  # (b) invalid reply → correction; valid reply → generation (CT-05) →
  # signed callback (CT-06) → PDF stored and approval requested (RF-01) →
  # lead e-mail filled and approved (RF-04, RF-09) → proposal e-mail accepted
  # (RF-11, RF-13).
  def answer_quote!(opportunity)
    email_conversation = opportunity.quote_request.email_conversation
    luciano_replies(email_conversation, block_without_payment)
    expect(opportunity.quote_request.reload).to be_correction_requested

    luciano_replies(email_conversation, valid_block)
    opportunity.quote_request.reload.proposal_versions.sole
  end

  def deliver_proposal!(opportunity)
    version = answer_quote!(opportunity)
    expect(version).to be_generating

    post_signed_callback(version)
    expect(response).to have_http_status(:ok)
    expect(version.reload).to be_awaiting_approval
    approve_with_lead_email!(opportunity, version)

    run_jobs { listener.message_updated(Events::Base.new('message_updated', Time.zone.now, { message: version.reload.sent_message })) }
    version.reload
  end

  def approve_with_lead_email!(opportunity, version)
    patch "/api/v1/accounts/#{account.id}/scan_solo/pipeline_opportunities/#{opportunity.id}",
          params: { email: 'ana@solar.example' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    run_jobs do
      post "/api/v1/accounts/#{account.id}/scan_solo/proposals/#{version.proposal_id}/approve",
           params: { proposal_version_id: version.id, correlation_id: SecureRandom.uuid }, headers: luciano.create_new_auth_token, as: :json
    end
    expect(response).to have_http_status(:ok)
  end

  def origin_messages(opportunity, origin)
    opportunity.conversation.messages.where("additional_attributes ->> 'scansolo_origin' = ?", origin)
  end

  def correlation_chain(quote_request)
    ScanSolo::AuditEvent.where(correlation_id: quote_request.correlation_id).order(:id).pluck(:event_type)
  end

  it '(a) qualifies a manual lead and sends 1 e-mail to the commercial recipient and 1 notice to the customer (RF-11, RF-12, RF-53)' do
    opportunity = qualify_manual_lead!

    expect(opportunity).to have_attributes(lead_source: 'manual', stage: 'qualificado')
    expect(ScanSolo::PipelineOpportunity.where(conversation_id: opportunity.conversation_id).count).to eq(1)
    expect(opportunity.lead_state).to be_concluida
    expect(opportunity.quote_request).to be_awaiting_reply
    mail = ActionMailer::Base.deliveries.sole
    expect(mail).to have_attributes(from: ['atendimento.comercial@scansolo.com.br'], to: ['comercial@scansolo.com.br'],
                                    subject: "Solicitação de orçamento ##{opportunity.id} — Solar Ltda")
    expect(origin_messages(opportunity, 'quote_notice').sole.content)
      .to eq('Recebi todas as informações, obrigado! Nosso comercial já está preparando seu orçamento. Assim que estiver pronto, envio por aqui.')
    expect(ScanSolo::ConversationExtension.resolve_for(opportunity.conversation)).to be_ai_active
  end

  # RF-01 / RF-11 / RF-13 (replaces OC/RF-29, OC/RF-30): the stored PDF goes
  # to the lead by e-mail after the approval, never over WhatsApp.
  it '(b) turns a corrected reply into an approved proposal e-mailed with the stored PDF and 1 follow-up (RF-01, RF-11, RF-13, RF-31)' do
    opportunity = qualify_manual_lead!

    version = deliver_proposal!(opportunity)

    expect(version).to have_attributes(status: 'sent', value: 12_500, quote_request_id: opportunity.quote_request.id,
                                       valid_until: Time.zone.parse('2026-11-04T00:00:00Z'), approved_by: luciano, approved_at: be_present)
    expect(version.document.blob.content_type).to eq('application/pdf')
    expect(version.sent_message).to have_attributes(inbox_id: email_inbox.id, conversation_id: version.proposal.email_conversation_id,
                                                    source_id: be_present)
    expect(version.sent_message.attachments.sole.file.blob.checksum).to eq(version.document.blob.checksum)
    expect(origin_messages(opportunity, 'proposal_notice').sole.additional_attributes.dig('template_params', 'processed_params').to_h)
      .not_to have_key('header')
    expect([opportunity.reload.stage, opportunity.cadence_enrollments.active.sole.cadence_definition.stage])
      .to eq(%w[proposta_enviada proposta_enviada])
    expect(%w[proposal proposal_follow_up].map { |origin| origin_messages(opportunity, origin).count }).to eq([0, 1])
  end

  it '(b) asks for the correction by e-mail, approves once and never calls send nor Make proposal.send (RF-04, RF-18, RF-21, RNF-01)' do
    opportunity = qualify_manual_lead!

    deliver_proposal!(opportunity)

    correction = opportunity.quote_request.email_conversation.messages.outgoing.order(:id).second
    expect(correction.content).to include('Condições de pagamento', ScanSolo::Quote::EmailComposer.empty_block)
    expect(ActionMailer::Base.deliveries.map(&:to)).to eq(([['comercial@scansolo.com.br']] * 3) + [['ana@solar.example']])
    expect(ScanSolo::Proposal::ApproveService).to have_received(:call).once
    expect(ScanSolo::Proposal::SendService).not_to have_received(:call)
    expect(ScanSolo::MakeRequest.pluck(:action)).to eq(['proposal.generate'])
    expect(transaction_open_at).to eq([[:make, false], [:download, false]])
  end

  it '(b) applies duplicated callbacks and reconciliations once (RNF-02)' do
    opportunity = qualify_manual_lead!
    version = deliver_proposal!(opportunity)

    post_signed_callback(version)
    run_jobs { listener.message_updated(Events::Base.new('message_updated', Time.zone.now, { message: version.sent_message })) }

    expect(response).to have_http_status(:ok)
    expect(version.proposal.email_conversation.messages.outgoing.count).to eq(1)
    expect(origin_messages(opportunity, 'proposal_notice').count).to eq(1)
    expect(origin_messages(opportunity, 'proposal_follow_up').count).to eq(1)
    expect(ScanSolo::ProposalVersion.count).to eq(1)
    expect(ScanSolo::PipelineStageEvent.where(opportunity: opportunity, to_stage: 'proposta_enviada').count).to eq(1)
  end

  it '(c) answers as before after the proposal, then hands a negotiation request to the commercial user (RF-34, RF-35..RF-38)' do
    opportunity = qualify_manual_lead!
    deliver_proposal!(opportunity)

    question = customer_says(opportunity, 'Vocês fazem a mobilização no sábado?')
    expect(run_turn(question, [])).to be_succeeded

    request = customer_says(opportunity, 'Consegue um desconto se eu pagar à vista?')
    run_turn(request, [{ 'action_id' => 'lead_state_update', 'params' => { 'negotiation_requested' => true } }])

    reply = opportunity.conversation.messages.outgoing.where(private: false, sender_type: 'AgentBot').where('id > ?', request.id).sole
    expect(reply.content).to eq('Vou verificar isso com nosso comercial. Só um momento.')
    expect([opportunity.reload.stage, ScanSolo::ConversationExtension.resolve_for(opportunity.conversation).ai_control_state,
            opportunity.conversation.reload.assignee]).to eq(['negociacao', 'awaiting_human', luciano])
    negotiation_mail = ActionMailer::Base.deliveries.last
    expect(negotiation_mail.to).to eq(['comercial@scansolo.com.br'])
    expect(negotiation_mail.html_part&.decoded || negotiation_mail.body.decoded).to include('Consegue um desconto se eu pagar à vista?')

    next_message = customer_says(opportunity, 'Alô?')
    expect(run_turn(next_message, [])).to have_attributes(invocation_status: 'suppressed', failure_reason: 'human_controlled')
  end

  it '(d) links an unthreaded reply from the pending list and generates the proposal (RF-19, RF-20, RF-24)' do
    opportunity = qualify_manual_lead!
    stray = create(:conversation, account: account, inbox: email_inbox)

    luciano_replies(stray, valid_block)

    get "/api/v1/accounts/#{account.id}/scan_solo/quote_replies", params: { status: 'pending' }, headers: admin.create_new_auth_token
    unmatched_reply = response.parsed_body.sole
    expect(unmatched_reply).to include('kind' => 'unmatched', 'conversation_id' => stray.id)

    run_jobs do
      post "/api/v1/accounts/#{account.id}/scan_solo/quote_replies/#{unmatched_reply['id']}/link",
           params: { quote_request_id: opportunity.quote_request.id }, headers: admin.create_new_auth_token, as: :json
    end

    expect(response).to have_http_status(:ok)
    quote_request = opportunity.quote_request.reload
    expect(quote_request).to be_replied
    expect(quote_request.proposal_versions.sole).to be_generating
    expect(ScanSolo::MakeRequest.sole.payload.dig('commercial', 'quote_request_id')).to eq(quote_request.id)
    expect(ScanSolo::AuditEvent.where(event_type: 'quote_reply.pending').count).to eq(1)
    expect(correlation_chain(quote_request)).to include('quote_reply.linked', 'quote_reply.accepted', 'proposal.generation_requested')
  end

  it "(e') recovers a misconfigured quote inbox through the manual resend without repeating the notice (RF-14, RF-56, RF-53)" do
    publish!(quote_inbox_id: nil)
    opportunity = qualify_manual_lead!

    sent = lambda {
      [ScanSolo::QuoteRequest.where(opportunity: opportunity).count, ActionMailer::Base.deliveries.size,
       origin_messages(opportunity, 'quote_notice').count]
    }
    misconfigured = ScanSolo::AuditEvent.where(subject: opportunity, event_type: 'quote_request.misconfigured')
    expect([*sent.call, misconfigured.count]).to eq([0, 0, 0, 1])

    publish!(quote_inbox_id: email_inbox.id)
    resend_path = "/api/v1/accounts/#{account.id}/scan_solo/pipeline_opportunities/#{opportunity.id}/quote_request/resend"
    run_jobs { post resend_path, headers: admin.create_new_auth_token, as: :json }

    expect(response).to have_http_status(:ok)
    first = response.parsed_body
    expect(sent.call).to eq([1, 1, 1])

    run_jobs { post resend_path, headers: admin.create_new_auth_token, as: :json }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('quote_request_id' => first['quote_request_id'], 'correlation_id' => first['correlation_id'])
    expect(sent.call).to eq([1, 2, 1])
    expect(ScanSolo::AuditEvent.where(event_type: 'quote_request.resent', actor: admin).count).to eq(2)
  end

  it '(e) returns the whole chain from the quote request correlation id and navigates it from the opportunity (RF-22, RNF-09)' do
    opportunity = qualify_manual_lead!
    version = deliver_proposal!(opportunity)

    quote_request = ScanSolo::PipelineOpportunity.find(opportunity.id).quote_request
    expect(correlation_chain(quote_request)).to eq(
      %w[quote_request.sent quote_reply.rejected quote_reply.accepted proposal.generation_requested proposal.generated
         proposal.approval_requested proposal.approved proposal.sent]
    )
    expect(quote_request.reply_message.conversation).to eq(quote_request.email_conversation)
    expect(quote_request.proposal_versions.sole).to eq(version)
    expect(ScanSolo::MakeRequest.find_by!(correlation_id: version.generate_correlation_id).action).to eq('proposal.generate')
  end

  it '(f) runs the whole flow with 0 real HTTP and 0 real SMTP (RNF-04)' do
    opportunity = qualify_manual_lead!
    deliver_proposal!(opportunity)

    expect(WebMock::Config.instance.allow_net_connect).to be(false)
    requested_hosts = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.map { |signature| signature.uri.host }.uniq
    expect(requested_hosts).to all(be_in(%w[waba.360dialog.io hook.make.example make.example]))
    expect(ActionMailer::Base.deliveries).not_to be_empty
    expect(ActionMailer::Base.deliveries.map(&:delivery_method)).to all(be_a(Mail::TestMailer))
  end
end
