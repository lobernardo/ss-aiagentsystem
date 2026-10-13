# frozen_string_literal: true

require 'rails_helper'

# scansolo-proposta-template-local T25: end-to-end proof of the local proposal
# generation — commercial reply → `.docx` template rendered → PDF converted by
# Gotenberg → approval request → explicit approval → e-mail to the lead (RF-10,
# RF-13..RF-16, RF-20, RF-24, RNF-02, RNF-04, RNF-05, RNF-09). Real ScanSolo
# services are wired together; only the true external boundaries are replaced:
# the LLM (MockLlmProvider), Gotenberg (WebMock answering with `sample.pdf`),
# the WhatsApp transport (360dialog stubbed by WebMock) and SMTP (ActionMailer
# `:test`). The Make credentials are present, so every assertion of "0 Make"
# proves the local mode's precedence (RF-01, RF-16). The template is a
# synthetic `.docx` built in memory and sent through the CT-05 upload API.
RSpec.describe 'ScanSolo proposta gerada localmente pelo template', type: :request do
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
  let(:convert_url) { 'http://gotenberg.test:3000/forms/libreoffice/convert' }
  let(:pdf) { file_fixture('sample.pdf').binread }
  let(:base_path) { "/api/v1/accounts/#{account.id}/scan_solo" }
  let(:lead_email) { 'ana@solar.example' }
  let(:transaction_open_at) { [] }
  let(:qualifying_llm) do
    lambda do |**kwargs|
      ScanSolo::TestMode::MockLlmProvider.call(
        **kwargs, fixture_actions: [{ 'action_id' => 'lead_state_update', 'params' => { 'intent' => 'orcamento' } },
                                    { 'action_id' => 'qualification_field', 'params' => { 'fields' => { 'area' => '800 m²' } } }]
      )
    end
  end

  # RNF-04: ActionMailer `:test` (the channel's SMTP switch is neutralized) and
  # the local mode on through the Gotenberg URL.
  around do |example|
    original = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :test
    with_modified_env(SCANSOLO_GOTENBERG_URL: 'http://gotenberg.test:3000') { example.run }
  ensure
    ActionMailer::Base.delivery_method = original
  end

  before do
    allow_any_instance_of(ConversationReplyMailer).to receive(:set_delivery_method) # rubocop:disable RSpec/AnyInstance
    ActionMailer::Base.deliveries.clear
    allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :scenario_url).and_return('https://hook.make.example/scenario-webhook')
    allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :secret).and_return('make-outbound-secret')
    allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :inbound_signing_secret).and_return('make-inbound-secret')
    allow(SafeFetch).to receive(:fetch).and_call_original

    stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
    stub_request(:post, 'https://waba.360dialog.io/v1/messages').to_return do
      { status: 200, body: { messages: [{ id: "wamid.#{SecureRandom.hex(6)}" }] }.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
    stub_gotenberg({ status: 200, body: pdf })

    create(:inbox_member, user: luciano, inbox: whatsapp_inbox)
    ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2, 24, 48, 96])
    ScanSolo::CadenceDefinition.create!(stage: 'proposta_enviada', version: 1, offsets: [24, 72])
    ScanSolo::TemplateMapping.create!(account: account, stage: 'lead_manual_inicial', step: nil, template_name: 'scansolo_lead_manual_inicial',
                                      language: 'pt_BR', params: [{ 'source' => 'contact_first_name' }])
    draft.update!(name: 'Agente ScanSolo', enabled: true, allowed_inbox_ids: [whatsapp_inbox.id], required_qualification_fields: ['Área'],
                  require_proposal_approval: false, quote_inbox_id: email_inbox.id, commercial_user_id: luciano.id)
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  # RNF-02: every Gotenberg call records whether a transaction was open.
  def stub_gotenberg(*responses)
    queue = responses.dup
    stub_request(:post, convert_url).to_return do
      transaction_open_at << ActiveRecord::Base.connection.current_transaction.joinable?
      queue.size > 1 ? queue.shift : queue.first
    end
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

  # Every native transport job and every ScanSolo job enqueued inside the block
  # runs, as Sidekiq would — the local generation job and its retries included.
  def run_jobs(&)
    perform_enqueued_jobs(only: [SendReplyJob, ScanSolo::QuoteRequestJob, ScanSolo::QuoteReplyJob, ScanSolo::ProposalLocalGenerationJob,
                                 ScanSolo::ProposalApprovalRequestJob, ScanSolo::ProposalDeliveryJob], &)
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
    run_jobs { ScanSolo::AiTurn::TurnOrchestrator.call(message: message, llm_provider: qualifying_llm) }
    expect(opportunity.reload.quote_request).to be_awaiting_reply
    fill_lead_email!(opportunity)
  end

  # The lead e-mail is known from the start, so "0 e-mails to the lead" is meaningful.
  def fill_lead_email!(opportunity)
    patch "#{base_path}/pipeline_opportunities/#{opportunity.id}", params: { email: lead_email }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    opportunity
  end

  def upload_template!
    file = Rack::Test::UploadedFile.new(StringIO.new(scan_solo_docx_valid), ScanSolo::Proposal::TemplateUploadService::CONTENT_TYPE,
                                        original_filename: 'proposta-sintetica.docx')
    post "#{base_path}/proposal_template", params: { file: file }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
  end

  def luciano_replies!(opportunity, content)
    quote_conversation = opportunity.quote_request.email_conversation
    message_created!(create(:message, account: account, inbox: email_inbox, conversation: quote_conversation, message_type: :incoming,
                                      sender: quote_conversation.contact, content: content))
  end

  def version_of(opportunity)
    opportunity.quote_request.reload.proposal_versions.sole
  end

  def approve!(version)
    run_jobs do
      post "#{base_path}/proposals/#{version.proposal_id}/approve",
           params: { proposal_version_id: version.id, correlation_id: SecureRandom.uuid }, headers: luciano.create_new_auth_token, as: :json
    end
    expect(response).to have_http_status(:ok)
    version.reload
  end

  # Reprocessar: answered while the version is still generating, with the job
  # enqueued (after commit, CT-02) under the new correlation id.
  def reprocess!(version)
    post "#{base_path}/proposals/#{version.proposal_id}/retry",
         params: { proposal_version_id: version.id, confirm_reprocess: false }, headers: luciano.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('id' => version.id, 'status' => 'generating')
    run_generation_job!(version.reload)
  end

  def run_generation_job!(version)
    jobs = enqueued_jobs.select { |job| job['job_class'] == ScanSolo::ProposalLocalGenerationJob.name }
    expect(jobs.pluck('arguments')).to eq([[version.id, version.generate_correlation_id]])
    run_jobs { ScanSolo::ProposalLocalGenerationJob.perform_now(*jobs.sole['arguments']) }
    version.reload
  end

  # Documents of the version, e-mails carrying its PDF, e-mails to the lead and Gotenberg requests.
  def counts(version)
    {
      documents: ActiveStorage::Attachment.where(record: version, name: 'document').count,
      proposal_emails: ActionMailer::Base.deliveries.count { |mail| mail.attachments.map(&:filename).include?("#{version.proposal_number}.pdf") },
      lead_emails: emails_to_lead.size,
      gotenberg: WebMock::RequestRegistry.instance.times_executed(WebMock::RequestPattern.new(:post, convert_url))
    }
  end

  def emails_to_lead
    ActionMailer::Base.deliveries.select { |mail| mail.to.include?(lead_email) }
  end

  def correlation_chain(opportunity)
    ScanSolo::AuditEvent.where(correlation_id: opportunity.quote_request.correlation_id).order(:id).pluck(:event_type)
  end

  # RF-16: the Make credentials are present, yet 0 MakeRequest and 0 HTTP to Make.
  def expect_no_make!
    requested_hosts = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.map { |signature| signature.uri.host }.uniq
    expect([ScanSolo::MakeRequest.count, requested_hosts - %w[waba.360dialog.io gotenberg.test]]).to eq([0, []])
    expect(a_request(:any, /make/)).not_to have_been_made
  end

  # RNF-04: no template text nor PDF bytes in any audit; RNF-02: Gotenberg never inside a transaction.
  def expect_no_content_in_audits!
    ScanSolo::AuditEvent.pluck(:payload).map(&:to_json).each do |payload|
      expect(payload).not_to include('Campo sintético', 'Rodapé sintético', '%PDF')
    end
    expect(transaction_open_at).to all(be(false))
  end

  it '(1) turns a valid reply into 1 awaiting_approval version with the PDF and 1 approval e-mail, nothing to the lead (RF-10, RF-24)' do
    upload_template!
    opportunity = qualified_opportunity!

    luciano_replies!(opportunity, block('12.500,00'))

    version = version_of(opportunity)
    expect(version).to have_attributes(status: 'awaiting_approval', value: 12_500, currency: 'BRL', artifact_url: nil, approved_at: nil)
    expect(counts(version)).to eq(documents: 1, proposal_emails: 1, lead_emails: 0, gotenberg: 1)
    expect([version.document.filename.to_s, version.document.content_type, Digest::SHA256.hexdigest(version.document.download)])
      .to eq(["#{version.proposal_number}.pdf", 'application/pdf', version.artifact_sha256])
    approval_request = version.approval_request_message
    expect([approval_request.content_attributes['to_emails'], approval_request.attachments.sole.file.blob.checksum])
      .to eq([['comercial@scansolo.com.br'], version.document.blob.checksum])
    expect(SafeFetch).not_to have_received(:fetch)
    expect_no_make!
    expect_no_content_in_audits!
  end

  it '(2) delivers to the lead only after the explicit approval, with the same blob (RF-15)' do
    upload_template!
    opportunity = qualified_opportunity!
    luciano_replies!(opportunity, block('12.500,00'))
    version = version_of(opportunity)

    # `require_proposal_approval: false` is published, yet nothing reaches the lead before Aprovar.
    expect([version.status, version.approved_at, version.sent_message, emails_to_lead]).to eq(['awaiting_approval', nil, nil, []])

    approve!(version)

    expect(version).to have_attributes(status: 'approved', approved_by: luciano)
    expect(emails_to_lead.map { |mail| mail.attachments.map(&:filename) }).to eq([["#{version.proposal_number}.pdf"]])
    expect(version.sent_message.attachments.sole.file.blob.checksum).to eq(version.document.blob.checksum)
    expect(SafeFetch).not_to have_received(:fetch)
    expect_no_make!
    expect_no_content_in_audits!
  end

  it '(3) re-running the reply job and the generation job keeps 1 version, 1 document and 1 Gotenberg request (RF-14)' do
    upload_template!
    opportunity = qualified_opportunity!
    reply = luciano_replies!(opportunity, block('12.500,00'))
    version = version_of(opportunity)

    run_jobs { ScanSolo::QuoteReplyJob.perform_now(reply.id) }
    run_jobs { ScanSolo::ProposalLocalGenerationJob.perform_now(version.id, version.generate_correlation_id) }

    expect(ScanSolo::ProposalVersion.count).to eq(1)
    expect(version.reload).to be_awaiting_approval
    expect(counts(version)).to eq(documents: 1, proposal_emails: 1, lead_emails: 0, gotenberg: 1)
    expect_no_make!
    expect_no_content_in_audits!
  end

  it '(4) fails without a template, then succeeds on Reprocessar after the upload, with the audit chain (RF-13, RF-19, RF-20)' do
    opportunity = qualified_opportunity!
    luciano_replies!(opportunity, block('12.500,00'))
    version = version_of(opportunity)
    failed_correlation_id = version.generate_correlation_id
    expect([version.status, version.failure_reason, version.value]).to eq(['failed', 'template_unavailable', nil])
    expect(counts(version)).to eq(documents: 0, proposal_emails: 0, lead_emails: 0, gotenberg: 0)

    upload_template!
    get "#{base_path}/status", headers: admin.create_new_auth_token, as: :json
    integration = response.parsed_body['proposal_integration']
    get "#{base_path}/proposals/#{version.proposal_id}", headers: luciano.create_new_auth_token, as: :json
    expect([integration, response.parsed_body['integration_state']]).to eq(%w[configured configured])

    reprocess!(version)

    expect([version.id, version.status, version.generate_correlation_id == failed_correlation_id, ScanSolo::ProposalVersion.count])
      .to eq([version_of(opportunity).id, 'awaiting_approval', false, 1])
    expect(counts(version)).to eq(documents: 1, proposal_emails: 1, lead_emails: 0, gotenberg: 1)
    expect(correlation_chain(opportunity) & %w[proposal.generation_failed proposal.retry_requested proposal.generated])
      .to eq(%w[proposal.generation_failed proposal.retry_requested proposal.generated])
    expect(ScanSolo::AuditEvent.find_by!(event_type: 'proposal.generation_failed').payload)
      .to include('reason' => 'template_unavailable', 'cause' => 'template', 'generate_correlation_id' => failed_correlation_id)
    expect_no_make!
    expect_no_content_in_audits!
  end

  it '(5) fails with provider_unavailable after 3 Gotenberg 5xx, never awaiting approval, then succeeds on Reprocessar (RF-11, RF-13)' do
    stub_gotenberg({ status: 503 }, { status: 503 }, { status: 503 }, { status: 200, body: pdf })
    upload_template!
    opportunity = qualified_opportunity!

    luciano_replies!(opportunity, block('12.500,00'))

    version = version_of(opportunity)
    expect([version.status, version.failure_reason, version.value]).to eq(['failed', 'provider_unavailable', nil])
    expect(counts(version)).to eq(documents: 0, proposal_emails: 0, lead_emails: 0, gotenberg: 3)
    expect(correlation_chain(opportunity)).not_to include('proposal.generated')

    reprocess!(version)

    expect([version.status, version.failure_reason]).to eq(['awaiting_approval', nil])
    expect(counts(version)).to eq(documents: 1, proposal_emails: 1, lead_emails: 0, gotenberg: 4)
    expect_no_make!
    expect_no_content_in_audits!
  end
end
