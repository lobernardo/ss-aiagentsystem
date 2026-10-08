# frozen_string_literal: true

require 'rails_helper'

# scansolo-proposta-aprovacao-email T32: end-to-end proof of the explicit
# approval and the e-mail delivery (RF-01..RF-18, RNF-01..RNF-04, RNF-06).
# Real ScanSolo services are wired together; only the true external
# boundaries are replaced: the LLM (MockLlmProvider), Make (scenario webhook
# and artifact stubbed by WebMock, callback signed with a test secret), the
# WhatsApp transport (360dialog stubbed by WebMock) and SMTP (ActionMailer
# `:test`). Native events reach ScanSolo::ConversationListener the way
# EventDispatcherJob delivers them, called here explicitly.
RSpec.describe 'ScanSolo proposta com aprovação e entrega por e-mail', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:luciano) { create(:user, account: account, role: :agent) }
  let(:message_templates) do
    [
      { 'name' => 'scansolo_lead_manual_inicial', 'status' => 'APPROVED', 'language' => 'pt_BR', 'category' => 'UTILITY',
        'components' => [{ 'type' => 'BODY', 'text' => 'Olá {{1}}, aqui é da ScanSolo.' }] },
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
  let(:base_path) { "/api/v1/accounts/#{account.id}/scan_solo" }
  let(:transaction_open_at) { [] }

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
    draft.update!(name: 'Agente ScanSolo', enabled: true, allowed_inbox_ids: [whatsapp_inbox.id], required_qualification_fields: ['Área'],
                  require_proposal_approval: false, quote_inbox_id: email_inbox.id, commercial_user_id: luciano.id)
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  def block(total)
    <<~TEXT
      Segue o orçamento.

      === RESPOSTA DO ORÇAMENTO ===
      Valor total: R$ #{total}
      Prazo/cronograma: 30 dias
      Escopo/atividades: Sondagem SPT
      Condições de pagamento: 50% na assinatura
      Observações comerciais:
      === FIM ===
    TEXT
  end

  # Every native transport job (WhatsApp and e-mail) and every ScanSolo job
  # enqueued inside the block runs, as Sidekiq would.
  def run_jobs(&)
    perform_enqueued_jobs(only: [SendReplyJob, ScanSolo::QuoteRequestJob, ScanSolo::QuoteReplyJob, ScanSolo::ProposalApprovalRequestJob,
                                 ScanSolo::ProposalDeliveryJob], &)
  end

  def message_created!(message)
    run_jobs { listener.message_created(Events::Base.new('message_created', Time.zone.now, { message: message })) }
    message
  end

  def qualified_opportunity!
    post "#{base_path}/pipeline_opportunities",
         params: { name: 'Ana Souza', phone_number: '+5511987654321', company: 'Solar Ltda', inbox_id: whatsapp_inbox.id },
         headers: admin.create_new_auth_token, as: :json
    opportunity = ScanSolo::PipelineOpportunity.find(response.parsed_body['id'])
    message = message_created!(create(:message, account: account, inbox: whatsapp_inbox, conversation: opportunity.conversation,
                                                message_type: :incoming, sender: opportunity.contact, content: 'Quero um orçamento de 800 m²'))
    provider = lambda do |**kwargs|
      ScanSolo::TestMode::MockLlmProvider.call(
        **kwargs, fixture_actions: [{ 'action_id' => 'lead_state_update', 'params' => { 'intent' => 'orcamento' } },
                                    { 'action_id' => 'qualification_field', 'params' => { 'fields' => { 'area' => '800 m²' } } }]
      )
    end
    run_jobs { ScanSolo::AiTurn::TurnOrchestrator.call(message: message, llm_provider: provider) }
    expect(opportunity.reload.quote_request).to be_awaiting_reply
    opportunity
  end

  def email_reply!(conversation, sender, content)
    message_created!(create(:message, account: account, inbox: email_inbox, conversation: conversation, message_type: :incoming,
                                      sender: sender, content: content))
  end

  def luciano_replies!(opportunity, content)
    quote_conversation = opportunity.quote_request.email_conversation
    email_reply!(quote_conversation, quote_conversation.contact, content)
  end

  def post_signed_callback!(version, total_value)
    body = {
      correlation_id: version.generate_correlation_id, idempotency_key: version.generate_correlation_id, action: 'proposal.generate',
      status: 'success',
      result: { proposal_version_id: version.id, artifact_url: artifact_url, total_value: total_value, currency: 'BRL',
                valid_until: '2026-11-04T00:00:00Z' }
    }.to_json
    run_jobs do
      post '/webhooks/scan_solo/make', params: body,
                                       headers: { 'CONTENT_TYPE' => 'application/json',
                                                  'X-Make-Signature' => OpenSSL::HMAC.hexdigest('SHA256', 'make-inbound-secret', body) }
    end
    expect(response).to have_http_status(:ok)
    version.reload
  end

  def proposal_action!(version, action, **params)
    run_jobs do
      post "#{base_path}/proposals/#{version.proposal_id}/#{action}",
           params: { proposal_version_id: version.id, **params }, headers: luciano.create_new_auth_token, as: :json
    end
    expect(response).to have_http_status(:ok)
    version.reload
  end

  def fill_lead_email!(opportunity)
    patch "#{base_path}/pipeline_opportunities/#{opportunity.id}", params: { email: 'ana@solar.example' },
                                                                   headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
  end

  def reconcile!(message)
    run_jobs { listener.message_updated(Events::Base.new('message_updated', Time.zone.now, { message: message.reload })) }
  end

  # reply → callback → awaiting_approval (PDF + CT-05) → approve → e-mail with
  # source_id → sent / proposta_enviada (+ notice and follow-up).
  def send_proposal!(opportunity)
    luciano_replies!(opportunity, block('12.500,00'))
    version = post_signed_callback!(opportunity.quote_request.reload.proposal_versions.sole, 12_500.0)
    fill_lead_email!(opportunity)
    proposal_action!(version, :approve, correlation_id: SecureRandom.uuid)
    reconcile!(version.sent_message)
    version.reload
  end

  def whatsapp_origin(opportunity, origin)
    opportunity.conversation.messages.where("additional_attributes ->> 'scansolo_origin' = ?", origin)
  end

  def correlation_chain(opportunity)
    ScanSolo::AuditEvent.where(correlation_id: opportunity.quote_request.correlation_id).order(:id).pluck(:event_type)
  end

  # The generate callback of the 1st version: awaiting approval with the PDF stored.
  def awaiting_approval_version!(opportunity)
    luciano_replies!(opportunity, block('12.500,00'))
    post_signed_callback!(opportunity.quote_request.reload.proposal_versions.sole, 12_500.0)
  end

  it '(a) stores the PDF and requests the approval on the quote thread, sending nothing to the lead (RF-01, RF-02)' do
    opportunity = qualified_opportunity!
    version = awaiting_approval_version!(opportunity)

    expect(version).to have_attributes(status: 'awaiting_approval', value: 12_500, approved_at: nil)
    expect(version.document.blob.content_type).to eq('application/pdf')
    approval_request = version.approval_request_message
    expect(approval_request).to have_attributes(conversation_id: opportunity.quote_request.email_conversation_id, message_type: 'outgoing')
    expect([approval_request.content_attributes['to_emails'], approval_request.attachments.sole.file.filename.to_s])
      .to eq([['comercial@scansolo.com.br'], "#{version.proposal_number}.pdf"])
    expect(approval_request.content).to include("/app/accounts/#{account.id}/scansolo/proposals")
    expect([opportunity.reload.stage, whatsapp_origin(opportunity, 'proposal_notice').count, version.proposal.email_conversation])
      .to eq(['qualificado', 0, nil])
  end

  it '(a) keeps an "aprovado" e-mail as a late reply and requires the lead e-mail before approving (RF-03, RF-08, RF-09)' do
    opportunity = qualified_opportunity!
    version = awaiting_approval_version!(opportunity)

    luciano_replies!(opportunity, 'Aprovado, pode enviar')
    post "#{base_path}/proposals/#{version.proposal_id}/approve", params: { proposal_version_id: version.id, correlation_id: SecureRandom.uuid },
                                                                  headers: luciano.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'lead_email_missing')
    expect(ScanSolo::QuoteReply.where(quote_request: opportunity.quote_request).pluck(:kind)).to eq(['late_reply'])
    expect(version.reload).to have_attributes(status: 'awaiting_approval', approved_at: nil)
    expect(ScanSolo::ProposalVersion.count).to eq(1)
  end

  it '(a) e-mails the approved proposal with the commercial CC and the PDF, with no notice before sent (RF-04, RF-11)' do
    opportunity = qualified_opportunity!
    version = awaiting_approval_version!(opportunity)
    fill_lead_email!(opportunity)

    proposal_action!(version, :approve, correlation_id: SecureRandom.uuid)

    expect(version).to have_attributes(status: 'approved', approved_by: luciano)
    email = version.sent_message
    expect(email).to have_attributes(inbox_id: email_inbox.id, conversation_id: version.proposal.email_conversation_id, source_id: be_present)
    expect(email.content_attributes).to include('to_emails' => ['ana@solar.example'], 'cc_emails' => ['comercial@scansolo.com.br'])
    expect(email.attachments.sole.file.blob.checksum).to eq(version.document.blob.checksum)
    expect(ActionMailer::Base.deliveries.last).to have_attributes(to: ['ana@solar.example'], cc: ['comercial@scansolo.com.br'])
    expect(ActionMailer::Base.deliveries.last.attachments.map(&:filename)).to eq(["#{version.proposal_number}.pdf"])
    expect([opportunity.reload.stage, whatsapp_origin(opportunity, 'proposal_notice').count]).to eq(['qualificado', 0])
  end

  it '(a) moves to sent and proposta_enviada on the e-mail source_id, then sends the notice and the follow-up (RF-13)' do
    opportunity = qualified_opportunity!

    version = send_proposal!(opportunity)

    expect(version).to be_sent
    expect(opportunity.reload).to be_proposta_enviada
    expect(opportunity.cadence_enrollments.active.sole.cadence_definition.stage).to eq('proposta_enviada')
    notice = whatsapp_origin(opportunity, 'proposal_notice').sole
    expect(notice.additional_attributes.dig('template_params', 'processed_params').to_h).not_to have_key('header')
    expect(whatsapp_origin(opportunity, 'proposal_follow_up').count).to eq(1)
  end

  it '(a) repeats the approval and the reconciliation without a 2nd e-mail or notice, all after commit (RF-12, RNF-01, RNF-02)' do
    opportunity = qualified_opportunity!
    version = send_proposal!(opportunity)

    proposal_action!(version, :approve, correlation_id: SecureRandom.uuid)
    reconcile!(version.sent_message)

    expect(version.proposal.email_conversation.messages.outgoing.count).to eq(1)
    expect(whatsapp_origin(opportunity, 'proposal_notice').count).to eq(1)
    expect(ScanSolo::AuditEvent.where(event_type: 'proposal.approved').count).to eq(1)
    expect(ScanSolo::MakeRequest.pluck(:action)).to eq(['proposal.generate'])
    expect(transaction_open_at).to eq([[:make, false], [:download, false]])
  end

  it '(b) generates version 2 on the same quote thread after a rejection (RF-05, RF-06, RF-07)' do
    opportunity = qualified_opportunity!
    first = awaiting_approval_version!(opportunity)

    proposal_action!(first, :reject, reason: 'Valor acima do combinado')
    expect(first).to have_attributes(status: 'rejected', rejection_reason: 'Valor acima do combinado', rejected_by: luciano)
    expect(opportunity.quote_request.reload).to be_awaiting_reply

    luciano_replies!(opportunity, block('9.000,00'))

    second = opportunity.quote_request.proposal_versions.find_by!(version_number: first.version_number + 1)
    expect(second).to have_attributes(status: 'generating', is_current: true, quote_request_id: first.quote_request_id)
    expect(first.reload).to have_attributes(status: 'rejected', is_current: false)
    expect(ScanSolo::MakeRequest.order(:id).last.payload.dig('commercial', 'total_value')).to eq(9000.0)
  end

  it '(b) e-mails the approved version 2 on the single proposal thread of the opportunity (RF-11)' do
    opportunity = qualified_opportunity!
    first = awaiting_approval_version!(opportunity)
    proposal_action!(first, :reject, reason: 'Valor acima do combinado')
    luciano_replies!(opportunity, block('9.000,00'))
    second = post_signed_callback!(opportunity.quote_request.proposal_versions.find_by!(version_number: 2), 9000.0)
    fill_lead_email!(opportunity)

    proposal_action!(second, :approve, correlation_id: SecureRandom.uuid)
    reconcile!(second.sent_message)

    expect(second.reload).to be_sent
    expect(first.reload.sent_message).to be_nil
    expect(Conversation.where(inbox: email_inbox).where("additional_attributes ->> 'scansolo_thread' = 'proposal_delivery'").sole)
      .to eq(second.proposal.email_conversation)
    expect(second.sent_message.conversation).to eq(second.proposal.email_conversation)
    expect(correlation_chain(opportunity)).to include('proposal.rejected', 'proposal.approved', 'proposal.sent')
  end

  it '(c) ignores a reply from the commercial CC on the proposal thread (RF-16, RF-18)' do
    opportunity = qualified_opportunity!
    version = send_proposal!(opportunity)
    interaction_at = opportunity.reload.last_customer_interaction_at
    commercial = opportunity.quote_request.email_conversation.contact

    email_reply!(version.proposal.email_conversation, commercial, 'Re: proposta — segue em cópia')

    expect(version.proposal.email_conversation.messages.incoming.count).to eq(1)
    expect(ScanSolo::CadenceAttempt.where(enrollment: opportunity.cadence_enrollments.active).scheduled.count).to eq(2)
    expect([ScanSolo::QuoteReply.count, opportunity.reload.last_customer_interaction_at]).to eq([0, interaction_at])
    expect(ScanSolo::AuditEvent.where(event_type: 'proposal.lead_email_reply').count).to eq(0)
  end

  it '(c) interrupts the whole cadence on the lead e-mail reply, with no quote reply nor AI turn (RF-16, RF-17, RF-18)' do
    opportunity = qualified_opportunity!
    version = send_proposal!(opportunity)
    scheduled = ScanSolo::CadenceAttempt.where(enrollment: opportunity.cadence_enrollments.active).scheduled
    expect(scheduled.count).to eq(2)

    lead_reply = email_reply!(version.proposal.email_conversation, opportunity.contact, 'Recebi a proposta, vou analisar.')

    expect(scheduled.count).to eq(0)
    expect(ScanSolo::AuditEvent.where(event_type: 'cadence.attempt_interrupted_by_reply').count).to eq(2)
    expect([ScanSolo::QuoteReply.count, ScanSolo::PipelineOpportunity.count, ScanSolo::AiTurn.where(message_id: lead_reply.id).count])
      .to eq([0, 1, 0])
    expect(opportunity.reload.last_customer_interaction_at).to be_within(1.second).of(lead_reply.created_at)
  end

  it '(d) returns the whole audit chain from the quote request correlation id (RNF-06)' do
    opportunity = qualified_opportunity!
    version = send_proposal!(opportunity)
    email_reply!(version.proposal.email_conversation, opportunity.contact, 'Recebi, obrigado.')

    expect(correlation_chain(opportunity)).to include(
      'proposal.generated', 'proposal.approval_requested', 'proposal.approved', 'proposal.sent', 'proposal.lead_email_reply',
      'cadence.attempt_interrupted_by_reply'
    )
    chain = correlation_chain(opportunity)
    expect(chain.index('proposal.generated')).to be < chain.index('proposal.approval_requested')
    expect(chain.index('proposal.approved')).to be < chain.index('proposal.sent')
  end

  it '(e) runs the whole flow with 0 real HTTP and 0 real SMTP (RNF-04)' do
    send_proposal!(qualified_opportunity!)

    expect(WebMock::Config.instance.allow_net_connect).to be(false)
    requested_hosts = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.map { |signature| signature.uri.host }.uniq
    expect(requested_hosts).to all(be_in(%w[waba.360dialog.io hook.make.example make.example]))
    expect(ActionMailer::Base.deliveries.map(&:delivery_method)).to all(be_a(Mail::TestMailer))
    expect(ActionMailer::Base.deliveries.size).to eq(3)
  end

  it '(f) schedules no cron for the approval and the delivery (RNF-03)' do
    scheduled_classes = YAML.load_file(Rails.root.join('config/schedule.yml')).values.pluck('class')

    expect(scheduled_classes.grep(/\AScanSolo::/)).to contain_exactly('ScanSolo::CadenceDueAttemptJob', 'ScanSolo::StaleTurnSweeperJob')
  end
end
