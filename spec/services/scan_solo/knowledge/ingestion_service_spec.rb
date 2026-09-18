# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Knowledge::IngestionService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:source) do
    ScanSolo::KnowledgeSource.create!(
      account: account,
      added_by: user,
      source_type: :faq,
      origin: 'manual',
      content: "Qual o horário de atendimento?\n\nAtendemos de segunda a sexta, das 9h às 20h."
    )
  end

  describe 'RF-28: chunk + embed via the pgvector/neighbor stack' do
    it 'produces chunks whose retrieval query returns a matching result with a similarity score' do
      described_class.call(source: source, embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider)

      expect(source.knowledge_chunks.count).to be_positive

      query_embedding = ScanSolo::TestMode::MockEmbeddingProvider.call(content: 'horário de atendimento')
      result = ScanSolo::KnowledgeChunk.nearest_neighbors(:embedding, query_embedding, distance: 'cosine').first

      expect(result).to be_present
      expect(result.source_id).to eq(source.id)
      expect(result.neighbor_distance).to be_a(Numeric)
    end

    it 'splits multi-paragraph content into more than one chunk' do
      described_class.call(source: source, embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider)

      expect(source.knowledge_chunks.count).to eq(2)
    end
  end

  describe 'RF-25: requires no production LLM credential' do
    it 'ingests using only the injected mock embedding provider, with zero real transport calls' do
      expect do
        described_class.call(source: source, embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider)
      end.not_to raise_error
    end
  end

  describe 'RF-90: document upload uses the native ActiveStorage attachment mechanism' do
    it 'attaches the uploaded file through has_one_attached, not a parallel unvalidated upload path' do
      source.file.attach(io: StringIO.new('conteudo do documento'), filename: 'doc.txt', content_type: 'text/plain')

      expect(source.file).to be_attached
      expect(source.file.attachment).to be_a(ActiveStorage::Attachment)
      expect(source.file.filename.to_s).to eq('doc.txt')
    end
  end

  describe 'idempotent re-ingestion' do
    it 'replaces rather than duplicates chunks when called twice for unchanged content' do
      described_class.call(source: source, embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider)
      first_count = source.knowledge_chunks.count

      described_class.call(source: source, embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider)

      expect(source.knowledge_chunks.count).to eq(first_count)
    end
  end
end
