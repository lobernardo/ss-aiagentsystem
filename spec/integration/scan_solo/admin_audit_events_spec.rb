# frozen_string_literal: true

require 'rails_helper'

# RF-50: one audit row per administrative event, with actor, subject, action
# and correlation id, and no secret value.
RSpec.describe 'ScanSolo administrative audit events', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/scan_solo" }
  let(:make_secret) { 'make-outbound-secret-value' }

  def expect_single_audit(event_type, subject_type:)
    events = ScanSolo::AuditEvent.where(event_type: event_type)
    expect(events.count).to eq(1)
    event = events.first
    expect(event).to have_attributes(actor: admin, subject_type: subject_type)
    expect(event.subject_id).to be_present
    expect(event.correlation_id).to be_present
    expect(event.payload.to_json).not_to include(make_secret)
    event
  end

  it 'records ai_agent_config.draft_updated including an opt-out keyword change' do
    put "#{base}/ai_agent_config/draft", params: { name: 'Agente', opt_out_keywords: %w[PARAR SAIR STOP CANCELAR] }, headers: headers, as: :json

    expect(response).to have_http_status(:success)
    event = expect_single_audit('ai_agent_config.draft_updated', subject_type: 'ScanSolo::AiAgentConfig')
    expect(event.payload['opt_out_keywords_changed']).to be true
  end

  it 'records ai_agent_config.published' do
    post "#{base}/ai_agent_config/publish", headers: headers, as: :json

    expect(response).to have_http_status(:success)
    expect_single_audit('ai_agent_config.published', subject_type: 'ScanSolo::AiAgentConfig')
  end

  describe 'knowledge sources' do
    let!(:source) do
      ScanSolo::KnowledgeSource.create!(account: account, added_by: admin, source_type: :faq, title: 'FAQ', content: 'Texto', origin: 'manual')
    end

    it 'records knowledge_source.created' do
      post "#{base}/knowledge/sources", params: { source_type: 'faq', title: 'Nova', content: 'Conteúdo', origin: 'manual' },
                                        headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect_single_audit('knowledge_source.created', subject_type: 'ScanSolo::KnowledgeSource')
    end

    it 'records knowledge_source.updated' do
      patch "#{base}/knowledge/sources/#{source.id}", params: { content: 'Novo texto' }, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect_single_audit('knowledge_source.updated', subject_type: 'ScanSolo::KnowledgeSource')
    end

    it 'records knowledge_source.deleted' do
      delete "#{base}/knowledge/sources/#{source.id}", headers: headers, as: :json

      expect(response).to have_http_status(:no_content)
      expect_single_audit('knowledge_source.deleted', subject_type: 'ScanSolo::KnowledgeSource')
    end

    it 'records knowledge_source.reindexed' do
      post "#{base}/knowledge/sources/#{source.id}/reindex", headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect_single_audit('knowledge_source.reindexed', subject_type: 'ScanSolo::KnowledgeSource')
    end
  end

  it 'records template_mapping.updated' do
    put "#{base}/cadence_templates",
        params: { stage: 'proposta_enviada', step: nil, template_name: 'proposta_v2', language: 'pt_BR', params: [{ source: 'contact_name' }] },
        headers: headers, as: :json

    expect(response).to have_http_status(:success)
    expect_single_audit('template_mapping.updated', subject_type: 'ScanSolo::TemplateMapping')
  end

  describe 'proposal retry and reprocess' do
    let(:contact) { create(:contact, account: account) }
    let(:conversation) { create(:conversation, account: account, contact: contact) }
    let(:opportunity) do
      ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
    end
    let(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
    let(:correlation_id) { SecureRandom.uuid }
    let!(:version) { proposal.versions.create!(status: :failed, failure_reason: 'timeout', generate_correlation_id: correlation_id) }
    let(:scenario_url) { 'https://hook.make.example/scenario-webhook' }

    before do
      allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :scenario_url).and_return(scenario_url)
      allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :secret).and_return(make_secret)
      allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :inbound_signing_secret).and_return('inbound')
      stub_request(:post, scenario_url).to_return(status: 503)
    end

    def retry_proposal(confirm_reprocess:)
      post "#{base}/proposals/#{proposal.id}/retry", params: { proposal_version_id: version.id, confirm_reprocess: confirm_reprocess },
                                                     headers: headers, as: :json
    end

    it 'records proposal.retry_requested with the new correlation id' do
      retry_proposal(confirm_reprocess: false)

      expect(response).to have_http_status(:success)
      event = expect_single_audit('proposal.retry_requested', subject_type: 'ScanSolo::ProposalVersion')
      expect(event.correlation_id).to eq(version.reload.generate_correlation_id)
    end

    it 'records proposal.reprocess_requested for a dead-lettered operation' do
      ScanSolo::MakeRequest.create!(account: account, correlation_id: correlation_id, idempotency_key: correlation_id, action: 'proposal.generate',
                                    payload: { proposal_version_id: version.id }, status: :failed, retry_count: 3)

      retry_proposal(confirm_reprocess: true)

      expect(response).to have_http_status(:success)
      expect_single_audit('proposal.reprocess_requested', subject_type: 'ScanSolo::ProposalVersion')
      expect(ScanSolo::AuditEvent.where(event_type: 'proposal.retry_requested')).to be_empty
    end
  end
end
