# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Knowledge::RetrievalService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, account: other_account, role: :agent) }

  let(:source) do
    ScanSolo::KnowledgeSource.create!(
      account: account, added_by: user, source_type: :faq, origin: 'manual',
      content: 'Qual o horário de atendimento?'
    )
  end

  def ingest!(knowledge_source)
    ScanSolo::Knowledge::IngestionService.call(source: knowledge_source, embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider)
  end

  describe 'RF-29: every result carries a source/evidence id traceable to its origin' do
    it 'returns the originating source id and type per result' do
      ingest!(source)

      response = described_class.call(account: account, query: 'horário', embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider)

      expect(response[:failure_reason]).to be_nil
      expect(response[:results]).not_to be_empty
      response[:results].each do |result|
        expect(result.source_id).to eq(source.id)
        expect(result.source_type).to eq('faq')
        expect(result.chunk_id).to be_present
        expect(result.similarity_score).to be_between(0, 1)
      end
    end
  end

  describe 'RF-30: disabling a source excludes its chunks without deleting them' do
    it 'removes a disabled source from subsequent retrieval results' do
      ingest!(source)
      before_disable = described_class.call(account: account, query: 'horário', embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider)
      expect(before_disable[:results]).not_to be_empty

      source.update!(enabled: false)

      response = described_class.call(account: account, query: 'horário', embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider)

      expect(response[:results]).to be_empty
      expect(ScanSolo::KnowledgeChunk.where(source: source)).to exist # data is not deleted
    end
  end

  describe 'account scoping' do
    it 'never returns another account chunks' do
      other_source = ScanSolo::KnowledgeSource.create!(
        account: other_account, added_by: other_user, source_type: :faq, origin: 'manual', content: 'outro conteudo'
      )
      ingest!(other_source)

      response = described_class.call(account: account, query: 'outro', embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider)

      expect(response[:results]).to be_empty
    end
  end

  describe 'RF-34: a vector-store outage continues the turn without RAG evidence' do
    it 'yields empty results and a recorded failure reason instead of raising' do
      ingest!(source)
      allow(ScanSolo::KnowledgeChunk).to receive(:joins).and_raise(ActiveRecord::StatementInvalid, 'connection outage')

      response = nil
      expect do
        response = described_class.call(account: account, query: 'horário', embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider)
      end.not_to raise_error

      expect(response[:results]).to eq([])
      expect(response[:failure_reason]).to be_present
    end
  end
end
