# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ScanSolo Knowledge Retrieval Tests API (CT-03)', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:agent) { create(:user, account: account, role: :administrator) }
  let(:base_path) { "/api/v1/accounts/#{account.id}/scan_solo/knowledge/retrieval_tests" }

  before do
    allow(ScanSolo::Knowledge::EmbeddingService).to receive(:call) do |content:, **|
      ScanSolo::TestMode::MockEmbeddingProvider.call(content: content)
    end
  end

  describe 'POST .../knowledge/retrieval_tests' do
    it 'returns ranked chunks with source/evidence ids for an operator-submitted query (RF-29, RF-32)' do
      source = ScanSolo::KnowledgeSource.create!(
        account: account, added_by: agent, source_type: :faq, origin: 'manual',
        content: 'Qual o horário de atendimento? Atendemos de segunda a sexta, das 9h às 20h.'
      )
      ScanSolo::Knowledge::IngestionService.call(source: source, embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider)

      post base_path, params: { query: 'horário de atendimento' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['results']).not_to be_empty
      expect(body['results'].first).to include('chunk_id', 'source_id', 'source_type', 'content_snippet', 'similarity_score')
      expect(body['results'].first['source_id']).to eq(source.id)
    end

    it 'rejects a blank query with a 422' do
      post base_path, params: { query: '' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'account without ScanSolo enabled' do
    let(:disabled_account) { create(:account, scansolo_enabled: false) }
    let(:disabled_agent) { create(:user, account: disabled_account, role: :agent) }

    it 'returns 404' do
      post "/api/v1/accounts/#{disabled_account.id}/scan_solo/knowledge/retrieval_tests",
           params: { query: 'x' }, headers: disabled_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
