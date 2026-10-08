# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ScanSolo Proposals API (CT-07)', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, :with_email, account: account, custom_attributes: { 'budget' => '5000' }) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado, owner: agent)
  end

  before do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente', enabled: true, required_qualification_fields: %w[budget], require_proposal_approval: false)
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  describe 'POST .../pipeline_opportunities/:id/proposals/generate' do
    let(:path) { "/api/v1/accounts/#{account.id}/scan_solo/pipeline_opportunities/#{opportunity.id}/proposals/generate" }

    def create_quote_request(status)
      ScanSolo::QuoteRequest.create!(
        account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid, status: status,
        commercial: { 'total_value' => '12500.0', 'schedule' => '30 dias', 'scope' => 'Sondagem SPT', 'payment_terms' => 'À vista' }
      )
    end

    # RF-25 (RNF-11): generation now requires the validated quote reply, so the example creates a `replied` request.
    it 'generates a proposal version from the validated quote reply (RF-73/RF-75, RF-24)' do
      quote_request = create_quote_request(:replied)
      ScanSolo::AiAgentConfig.draft_for!(account).update!(required_qualification_fields: ['Área'])
      ScanSolo::AiAgent::PublishService.new(account: account).call
      ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state)
                                 .apply_field!(key: 'area', value: '800 m²', status: 'confirmado', source_message_id: nil)

      post path, params: { correlation_id: SecureRandom.uuid }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('awaiting_approval')
      expect(response.parsed_body['is_current']).to be true
      expect(ScanSolo::ProposalVersion.sole.quote_request).to eq(quote_request)
    end

    # RF-25 (RNF-11): with the validated reply in place, the field gate still rejects.
    it 'rejects generation with required fields incomplete (RF-74)' do
      create_quote_request(:replied)
      contact.update!(custom_attributes: {})

      post path, params: { correlation_id: SecureRandom.uuid }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(ScanSolo::Proposal.where(opportunity: opportunity)).to be_none
    end

    it 'rejects generation without a quote request (RF-25)' do
      post path, params: { correlation_id: SecureRandom.uuid }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.to_s).to include('sem resposta de orçamento validada')
      expect(ScanSolo::ProposalVersion.count).to eq(0)
    end

    it 'rejects generation while the quote request awaits the reply (RF-25)' do
      create_quote_request(:awaiting_reply)

      post path, params: { correlation_id: SecureRandom.uuid }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(ScanSolo::ProposalVersion.count).to eq(0)
    end

    it 'rejects generation while the request has an awaiting_approval version (RF-07)' do
      quote_request = create_quote_request(:replied)
      ScanSolo::Proposal.create!(opportunity: opportunity).versions.create!(status: :awaiting_approval, quote_request: quote_request)

      expect do
        post path, params: { correlation_id: SecureRandom.uuid }, headers: agent.create_new_auth_token, as: :json
      end.not_to change(ScanSolo::ProposalVersion, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.to_s).to include('sem resposta de orçamento validada')
    end
  end

  describe 'POST .../proposals/:id/approve and .../reject (CT-02, CT-03)' do
    let!(:quote_request) do
      ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid, status: :replied)
    end
    let!(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
    let!(:version) do
      proposal.versions.create!(status: :awaiting_approval, quote_request: quote_request, value: 1000, currency: 'BRL')
    end
    let(:path) { "/api/v1/accounts/#{account.id}/scan_solo/proposals/#{proposal.id}" }
    let(:approved_audits) { ScanSolo::AuditEvent.where(event_type: 'proposal.approved') }

    def approve(user = admin)
      post "#{path}/approve", params: { proposal_version_id: version.id, correlation_id: SecureRandom.uuid },
                              headers: user.create_new_auth_token, as: :json
    end

    def reject(reason, user = admin)
      post "#{path}/reject", params: { proposal_version_id: version.id, reason: reason }, headers: user.create_new_auth_token, as: :json
    end

    it 'approves once: a repeat returns 200 with 1 audit and 1 delivery job in total (RF-04, RNF-02)' do
      approve

      expect(response.parsed_body).to include('status' => 'approved', 'approved_by' => { 'id' => admin.id, 'name' => admin.name })
      expect(version.reload).to have_attributes(status: 'approved', approved_by_id: admin.id)

      approve

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('approved')
      expect(approved_audits.count).to eq(1)
      expect(ScanSolo::ProposalDeliveryJob).to have_been_enqueued.exactly(:once)
    end

    it 'records one audit for two concurrent approvals (RF-04, RNF-02)' do
      headers = admin.create_new_auth_token
      params = { proposal_version_id: version.id, correlation_id: SecureRandom.uuid }

      Array.new(2) { Thread.new { open_session.post("#{path}/approve", params: params, headers: headers, as: :json) } }.each(&:join)

      expect(approved_audits.count).to eq(1)
      expect(version.reload).to be_approved
    end

    it 'lets the published commercial user approve and forbids any other agent (RF-04, Q-01)' do
      commercial = create(:user, account: account, role: :agent)
      ScanSolo::AiAgentConfig.draft_for!(account).update!(commercial_user_id: commercial.id)
      ScanSolo::AiAgent::PublishService.new(account: account).call

      approve(agent)

      expect(response).to have_http_status(:forbidden)
      expect(approved_audits).to be_none

      approve(commercial)

      expect(response).to have_http_status(:success)
      expect(version.reload.approved_by).to eq(commercial)
    end

    it 'refuses the approval while the lead has no valid e-mail and changes nothing (RF-08)' do
      contact.update!(email: nil)

      approve

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'lead_email_missing')
      expect(version.reload).to be_awaiting_approval
      expect(approved_audits).to be_none
    end

    it 'rejects with a reason and reopens the quote request (RF-05, RF-06)' do
      reject('Valor acima do combinado')

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include(
        'status' => 'rejected', 'rejection_reason' => 'Valor acima do combinado', 'rejected_by' => { 'id' => admin.id, 'name' => admin.name }
      )
      expect(response.parsed_body['rejected_at']).to be_present
      expect(quote_request.reload).to be_awaiting_reply
      expect(ScanSolo::AuditEvent.where(event_type: 'proposal.rejected').count).to eq(1)
    end

    it 'refuses a blank reason with reason_required (CT-03)' do
      reject('  ')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'reason_required')
      expect(version.reload).to be_awaiting_approval
    end

    it 'refuses rejecting an approved version with not_awaiting_approval (CT-03)' do
      version.update!(status: :approved)

      reject('Tarde demais')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'not_awaiting_approval')
      expect(version.reload).to be_approved
    end

    it 'forbids a rejection by an agent that is not the commercial user (RF-05)' do
      reject('Motivo', agent)

      expect(response).to have_http_status(:forbidden)
      expect(version.reload).to be_awaiting_approval
    end
  end

  describe 'POST .../proposals/:id/send (RF-21, CT-04)' do
    let!(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
    let!(:version) { proposal.versions.create!(status: :generated, value: 1000, currency: 'BRL', artifact_url: 'https://x.test/a.pdf') }

    # RF-21 / CT-04 replace the OC/RF-77/RF-78 send expectations: the legacy send never emits proposal.send.
    def send_proposal(target = version)
      post "/api/v1/accounts/#{account.id}/scan_solo/proposals/#{proposal.id}/send",
           params: { proposal_version_id: target.id, correlation_id: SecureRandom.uuid },
           headers: agent.create_new_auth_token, as: :json
    end

    it 'rejects sending a version that is not approved with approval_required and 0 Make requests' do
      %i[generated awaiting_approval].each do |status|
        version.update!(status: status)

        expect { send_proposal }.not_to change(ScanSolo::MakeRequest, :count)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq('error' => 'approval_required')
      end
    end

    it 'rejects sending a sent version with already_sent' do
      version.update!(status: :sent)

      send_proposal

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'already_sent')
    end

    it 'rejects sending a stale version with not_current_version' do
      version.update!(status: :rejected)
      proposal.versions.create!(status: :approved, value: 1200, currency: 'BRL') # becomes current

      send_proposal

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'not_current_version')
    end
  end

  describe 'GET .../proposals (UI-08 data source)' do
    let!(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
    let!(:version) { proposal.versions.create!(status: :generated, value: 1000, currency: 'BRL') }

    it 'lists proposals with their versions for the account' do
      get "/api/v1/accounts/#{account.id}/scan_solo/proposals", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body.length).to eq(1)
      expect(body.first['id']).to eq(proposal.id)
      expect(body.first['versions'].first['id']).to eq(version.id)
      expect(body.first['contact_name']).to eq(contact.name)
    end

    it 'exposes proposal_number, valid_until, document_url and the quote request status (CT-02, UI-05)' do
      version.update!(valid_until: 15.days.from_now)
      version.document.attach(io: StringIO.new('%PDF-1.4'), filename: 'proposta.pdf', content_type: 'application/pdf')
      ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid, status: :replied)

      get "/api/v1/accounts/#{account.id}/scan_solo/proposals", headers: agent.create_new_auth_token, as: :json

      body = response.parsed_body.first
      expect(body['quote_request_status']).to eq('replied')
      expect(body['versions'].first).to include('proposal_number' => version.reload.proposal_number)
      expect(body['versions'].first['valid_until']).to be_present
      expect(body['versions'].first['document_url']).to include('proposta.pdf')
    end

    it 'keeps a historical approved version with its status and approved_at (RNF-10)' do
      approved_at = 2.days.ago.change(usec: 0)
      legacy = proposal.versions.create!(status: :approved, approved_at: approved_at, value: 900, currency: 'BRL')

      get "/api/v1/accounts/#{account.id}/scan_solo/proposals", headers: agent.create_new_auth_token, as: :json

      body = response.parsed_body.first
      expect(body['quote_request_status']).to be_nil
      legacy_json = body['versions'].find { |item| item['id'] == legacy.id }
      expect(legacy_json).to include('status' => 'approved', 'document_url' => nil, 'valid_until' => nil)
      expect(Time.zone.parse(legacy_json['approved_at'])).to eq(approved_at)
    end

    it 'reads legacy generated/approved/sent versions with the new fields (CT-01, RF-26)' do
      proposal.versions.create!(status: :approved, approved_at: 1.day.ago, value: 900, currency: 'BRL')
      proposal.versions.create!(status: :sent, value: 900, currency: 'BRL')

      get "/api/v1/accounts/#{account.id}/scan_solo/proposals/#{proposal.id}", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['lead_email_present']).to be(true)
      expect(body['versions'].pluck('status')).to eq(%w[generated approved sent])
      expect(body['versions']).to all(include(
                                        'approved_by' => nil, 'rejected_at' => nil, 'rejected_by' => nil, 'rejection_reason' => nil,
                                        'delivery' => { 'email_status' => nil, 'notice_status' => nil }
                                      ))
    end

    it 'exposes the e-mail and notice delivery states (CT-01)' do
      email_inbox = create(:channel_email, account: account).inbox
      email_conversation = create(:conversation, account: account, inbox: email_inbox, contact: contact)
      email = create(:message, conversation: email_conversation, message_type: :outgoing, source_id: '<proposal@scansolo>')
      notice = create(:message, conversation: conversation, message_type: :outgoing, status: :failed)
      version.update!(status: :sent, sent_message: email, notice_message: notice)
      contact.update!(email: nil)

      get "/api/v1/accounts/#{account.id}/scan_solo/proposals", headers: agent.create_new_auth_token, as: :json

      body = response.parsed_body.first
      expect(body['lead_email_present']).to be(false)
      expect(body['versions'].first['delivery']).to eq('email_status' => 'sent', 'notice_status' => 'failed')

      email.update!(source_id: nil)
      version.update!(notice_message: nil, notice_failure_reason: 'template_missing')
      get "/api/v1/accounts/#{account.id}/scan_solo/proposals", headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body.first['versions'].first['delivery']).to eq('email_status' => 'pending', 'notice_status' => 'blocked')
    end

    it 'returns 404 when ScanSolo is disabled for the account' do
      account.update!(scansolo_enabled: false)

      get "/api/v1/accounts/#{account.id}/scan_solo/proposals", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'RF-40/RF-42: retry through Make, dead letter and reprocess' do
    let!(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
    let(:correlation_id) { SecureRandom.uuid }
    let!(:version) do
      proposal.versions.create!(status: :failed, failure_reason: 'timeout', generate_correlation_id: correlation_id)
    end
    let(:scenario_url) { 'https://hook.make.example/scenario-webhook' }

    before do
      allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :scenario_url).and_return(scenario_url)
      allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :secret).and_return('make-secret')
      allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :inbound_signing_secret).and_return('make-inbound')
      stub_request(:post, scenario_url).to_return(status: 502)
      ScanSolo::MakeRequest.create!(account: account, correlation_id: correlation_id, idempotency_key: correlation_id,
                                    action: 'proposal.generate', payload: { proposal_version_id: version.id }, status: :failed)
    end

    def retry_proposal(confirm_reprocess: false)
      post "/api/v1/accounts/#{account.id}/scan_solo/proposals/#{proposal.id}/retry",
           params: { proposal_version_id: version.id, confirm_reprocess: confirm_reprocess }, headers: admin.create_new_auth_token, as: :json
    end

    it 'lists the operation in the executions dead letters after 3 failed retries and rejects a 4th plain retry' do
      3.times do
        retry_proposal
        expect(response).to have_http_status(:success)
      end

      get "/api/v1/accounts/#{account.id}/scan_solo/executions", headers: admin.create_new_auth_token, as: :json
      dead_letters = response.parsed_body.dig('make_errors', 'dead_letters')
      expect(dead_letters.pluck('correlation_id')).to eq([version.reload.generate_correlation_id])

      expect { retry_proposal }.not_to change(ScanSolo::MakeRequest, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'reprocesses a dead letter with confirmation through a new MakeRequest' do
      3.times { retry_proposal }

      expect { retry_proposal(confirm_reprocess: true) }.to change(ScanSolo::MakeRequest, :count).by(1)
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['retry_count']).to eq(4)
    end

    it 'exposes failure_reason, correlation_id, retry_count and dead_letter on the failed version' do
      retry_proposal

      get "/api/v1/accounts/#{account.id}/scan_solo/proposals/#{proposal.id}", headers: agent.create_new_auth_token, as: :json

      body = response.parsed_body
      expect(body).to include('integration_state' => 'configured', 'owner_id' => agent.id)
      expect(body['versions'].first).to include(
        'status' => 'failed', 'failure_reason' => 'provider_unavailable', 'correlation_id' => version.reload.generate_correlation_id,
        'retry_count' => 1, 'dead_letter' => false
      )
    end
  end

  describe 'authorization and production integration gates' do
    let!(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
    let!(:version) { proposal.versions.create!(status: :failed, failure_reason: 'timeout') }
    let(:path) { "/api/v1/accounts/#{account.id}/scan_solo/proposals/#{proposal.id}" }

    it 'rejects agent approve, reject and retry, and send by a non-owner (RF-15)' do
      %w[approve reject retry].each do |action|
        post "#{path}/#{action}", params: { proposal_version_id: version.id, correlation_id: SecureRandom.uuid, reason: 'x' },
                                  headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:forbidden)
      end
      opportunity.update!(owner: nil)
      post "#{path}/send", params: { proposal_version_id: version.id, correlation_id: SecureRandom.uuid },
                           headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'allows an administrator to retry a safely failed generation' do
      post "#{path}/retry", params: { proposal_version_id: version.id, confirm_reprocess: false },
                            headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(version.reload).to be_awaiting_approval
    end

    it 'rejects a retry without a boolean confirm_reprocess (CT-04 boundary)' do
      post "#{path}/retry", params: { proposal_version_id: version.id, confirm_reprocess: 'yes' },
                            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(version.reload).to be_failed
    end

    it 'returns 422 for a non-retryable failure reason' do
      version.update!(failure_reason: 'template_missing')

      post "#{path}/retry", params: { proposal_version_id: version.id, confirm_reprocess: false },
                            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    # RF-21: send never reaches Make, so it has no integration gate.
    it 'blocks generate and retry in production without writing proposal or request rows' do
      allow(Rails.env).to receive(:production?).and_return(true)
      allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, anything).and_return(nil)
      expect(ScanSolo::Proposal::MockProvider).not_to receive(:request_generation)
      paths = ["/api/v1/accounts/#{account.id}/scan_solo/pipeline_opportunities/#{opportunity.id}/proposals/generate", "#{path}/retry"]
      original_attributes = version.attributes
      paths.each do |endpoint|
        expect do
          post endpoint, params: { proposal_version_id: version.id, correlation_id: SecureRandom.uuid, confirm_reprocess: false },
                         headers: admin.create_new_auth_token, as: :json
        end.not_to(change { [ScanSolo::ProposalVersion.count, ScanSolo::MakeRequest.count] })
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq('error' => 'proposal_integration_not_configured')
        expect(version.reload.attributes).to eq(original_attributes)
      end
    end
  end
end
