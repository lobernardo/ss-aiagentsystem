# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ScanSolo Proposals API (CT-07)', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, custom_attributes: { 'budget' => '5000' }) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end

  before do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente', enabled: true, required_qualification_fields: %w[budget], require_proposal_approval: false)
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  describe 'POST .../pipeline_opportunities/:id/proposals/generate' do
    let(:path) { "/api/v1/accounts/#{account.id}/scan_solo/pipeline_opportunities/#{opportunity.id}/proposals/generate" }

    it 'generates a proposal version (RF-73/RF-75)' do
      post path, params: { correlation_id: SecureRandom.uuid }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('generated')
      expect(response.parsed_body['is_current']).to be true
    end

    it 'rejects generation with required fields incomplete (RF-74)' do
      contact.update!(custom_attributes: {})

      post path, params: { correlation_id: SecureRandom.uuid }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(ScanSolo::Proposal.where(opportunity: opportunity)).to be_none
    end
  end

  describe 'POST .../proposals/:id/approve and .../send' do
    let!(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
    let!(:version) { proposal.versions.create!(status: :generated, value: 1000, currency: 'BRL', artifact_url: 'https://x.test/a.pdf') }

    it 'approves the current version' do
      post "/api/v1/accounts/#{account.id}/scan_solo/proposals/#{proposal.id}/approve",
           params: { proposal_version_id: version.id, correlation_id: SecureRandom.uuid },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('approved')
    end

    it 'sends the current version when approval is not required' do
      post "/api/v1/accounts/#{account.id}/scan_solo/proposals/#{proposal.id}/send",
           params: { proposal_version_id: version.id, correlation_id: SecureRandom.uuid },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('sent')
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
  end
end
