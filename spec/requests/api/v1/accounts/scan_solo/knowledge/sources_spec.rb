# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ScanSolo Knowledge Sources API', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base_path) { "/api/v1/accounts/#{account.id}/scan_solo/knowledge/sources" }

  before do
    allow(ScanSolo::Knowledge::EmbeddingService).to receive(:call) do |content:, **|
      ScanSolo::TestMode::MockEmbeddingProvider.call(content: content)
    end
  end

  describe 'POST .../knowledge/sources' do
    it 'creates a FAQ entry, ingests it, and returns the persisted source' do
      post base_path, params: {
        source_type: 'faq',
        title: 'Horário de atendimento',
        content: 'Atendemos de segunda a sexta, das 9h às 20h.',
        origin: 'manual'
      }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['source_type']).to eq('faq')
      expect(body['chunks_count']).to be_positive
      expect(ScanSolo::KnowledgeSource.find(body['id']).added_by).to eq(agent)
    end

    it 'attaches an uploaded document through the native ActiveStorage mechanism (RF-90)' do
      file = fixture_file_upload(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf')

      post base_path, params: {
        source_type: 'document', title: 'Política de garantia',
        content: 'Produtos têm 90 dias de garantia contra defeitos de fabricação.',
        origin: 'upload', file: file
      }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['file_attached']).to be true
      expect(ScanSolo::KnowledgeSource.find(body['id']).file).to be_attached
    end
  end

  describe 'GET .../knowledge/sources' do
    it 'lists sources for the account' do
      ScanSolo::KnowledgeSource.create!(account: account, added_by: agent, source_type: :faq, origin: 'manual', content: 'x')

      get base_path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.length).to eq(1)
    end
  end

  describe 'PATCH .../knowledge/sources/:id (enable/disable)' do
    it 'toggles enabled without re-triggering ingestion' do
      source = ScanSolo::KnowledgeSource.create!(account: account, added_by: agent, source_type: :faq, origin: 'manual', content: 'x')

      patch "#{base_path}/#{source.id}", params: { enabled: false }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(source.reload.enabled).to be false
    end
  end

  describe 'POST .../knowledge/sources/:id/reindex (RF-31)' do
    it 'reindexes without duplicating chunks when called twice' do
      source = ScanSolo::KnowledgeSource.create!(
        account: account, added_by: agent, source_type: :faq, origin: 'manual', content: 'Conteúdo de teste.'
      )
      ScanSolo::Knowledge::IngestionService.call(source: source, embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider)
      first_count = source.knowledge_chunks.count

      post "#{base_path}/#{source.id}/reindex", headers: agent.create_new_auth_token, as: :json
      post "#{base_path}/#{source.id}/reindex", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(source.knowledge_chunks.reload.count).to eq(first_count)
    end
  end

  describe 'DELETE .../knowledge/sources/:id (RF-33)' do
    it 'removes the source content from future retrieval' do
      source = ScanSolo::KnowledgeSource.create!(
        account: account, added_by: agent, source_type: :faq, origin: 'manual', content: 'Conteúdo removível.'
      )
      ScanSolo::Knowledge::IngestionService.call(source: source, embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider)

      delete "#{base_path}/#{source.id}", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:no_content)
      expect(ScanSolo::KnowledgeSource.where(id: source.id)).not_to exist
      expect(ScanSolo::KnowledgeChunk.where(source_id: source.id)).not_to exist

      retrieval = ScanSolo::Knowledge::RetrievalService.call(
        account: account, query: 'removível', embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider
      )
      expect(retrieval[:results]).to be_empty
    end
  end

  describe 'account without ScanSolo enabled' do
    let(:disabled_account) { create(:account, scansolo_enabled: false) }
    let(:disabled_agent) { create(:user, account: disabled_account, role: :agent) }

    it 'returns 404' do
      get "/api/v1/accounts/#{disabled_account.id}/scan_solo/knowledge/sources", headers: disabled_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
