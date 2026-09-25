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

    it 'splits paragraphs separated by CRLF (browser form submission)' do
      source.update_columns(content: "Pergunta 1?\r\nResposta 1.\r\n\r\nPergunta 2?\r\nResposta 2.")
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

  describe 'RF-44/RF-45: indexing state' do
    it 'marks the source indexed with indexed_at and chunk_count' do
      described_class.call(source: source, embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider)

      expect(source.reload).to have_attributes(index_status: 'indexed', chunk_count: 2, index_error: nil)
      expect(source.indexed_at).to be_present
    end

    it 'marks the source failed with a pt-BR error and keeps the previous chunks on an embedding outage' do
      described_class.call(source: source, embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider)
      previous_ids = source.knowledge_chunks.pluck(:id)
      failing_provider = Class.new do
        def self.call(**)
          raise Faraday::ConnectionFailed, 'embedding endpoint unreachable'
        end
      end

      source.update_columns(content: 'Conteúdo novo que não chega a ser indexado.') # rubocop:disable Rails/SkipsModelValidations
      described_class.call(source: source, embedding_provider: failing_provider)

      expect(source.reload).to have_attributes(index_status: 'failed', chunk_count: 2)
      expect(source.index_error).to eq('Não foi possível indexar a fonte (Faraday::ConnectionFailed). Tente reindexar mais tarde.')
      expect(source.knowledge_chunks.pluck(:id)).to match_array(previous_ids)
    end

    it 'marks an attachment-only source failed with the reason, never indexed with 0 chunks' do
      source.update_columns(content: nil) # rubocop:disable Rails/SkipsModelValidations
      source.file.attach(io: StringIO.new('%PDF-1.4'), filename: 'catalogo.pdf', content_type: 'application/pdf')

      described_class.call(source: source, embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider)

      expect(source.reload).to have_attributes(index_status: 'failed', chunk_count: 0)
      expect(source.index_error).to eq(described_class::ATTACHMENT_ONLY_ERROR)
    end

    it 'marks an empty source failed' do
      source.update_columns(content: "  \n\n ") # rubocop:disable Rails/SkipsModelValidations

      described_class.call(source: source, embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider)

      expect(source.reload).to have_attributes(index_status: 'failed', index_error: described_class::EMPTY_CONTENT_ERROR)
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
