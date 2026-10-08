# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ScanSolo Proposals API (CT-07)', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, custom_attributes: { 'budget' => '5000' }) }
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
  end

  describe 'POST .../proposals/:id/approve and .../send' do
    let!(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
    let!(:version) { proposal.versions.create!(status: :generated, value: 1000, currency: 'BRL', artifact_url: 'https://x.test/a.pdf') }

    it 'approves the current version' do
      post "/api/v1/accounts/#{account.id}/scan_solo/proposals/#{proposal.id}/approve",
           params: { proposal_version_id: version.id, correlation_id: SecureRandom.uuid },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('approved')
    end

    it 'sends the current version when approval is not required' do
      post "/api/v1/accounts/#{account.id}/scan_solo/proposals/#{proposal.id}/send",
           params: { proposal_version_id: version.id, correlation_id: SecureRandom.uuid },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      # RF-41: the native proposal message exists; `sent` waits for delivery acceptance.
      expect(version.reload.sent_message).to be_present
      expect(response.parsed_body['status']).to eq('generated')
    end

    it 'rejects sending a stale version (RF-77)' do
      proposal.versions.create!(status: :generated, value: 1200, currency: 'BRL') # becomes current

      post "/api/v1/accounts/#{account.id}/scan_solo/proposals/#{proposal.id}/send",
           params: { proposal_version_id: version.id, correlation_id: SecureRandom.uuid },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rejects sending without approval when approval is required (RF-78)' do
      draft = ScanSolo::AiAgentConfig.draft_for!(account)
      draft.update!(require_proposal_approval: true)
      ScanSolo::AiAgent::PublishService.new(account: account).call

      post "/api/v1/accounts/#{account.id}/scan_solo/proposals/#{proposal.id}/send",
           params: { proposal_version_id: version.id, correlation_id: SecureRandom.uuid },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
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

    it 'rejects agent approve and retry, and send by a non-owner' do
      %w[approve retry].each do |action|
        post "#{path}/#{action}", params: { proposal_version_id: version.id, correlation_id: SecureRandom.uuid },
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

    it 'blocks generate, send and retry in production without writing proposal or request rows' do
      allow(Rails.env).to receive(:production?).and_return(true)
      allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, anything).and_return(nil)
      expect(ScanSolo::Proposal::MockProvider).not_to receive(:request_generation)
      expect(ScanSolo::Proposal::MockProvider).not_to receive(:request_send)
      paths = [
        "/api/v1/accounts/#{account.id}/scan_solo/pipeline_opportunities/#{opportunity.id}/proposals/generate",
        "#{path}/send", "#{path}/retry"
      ]
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
