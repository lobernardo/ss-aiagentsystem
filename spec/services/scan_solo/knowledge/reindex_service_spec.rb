# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Knowledge::ReindexService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:source) do
    ScanSolo::KnowledgeSource.create!(
      account: account,
      added_by: user,
      source_type: :document,
      origin: 'upload',
      content: 'Política de garantia: produtos têm 90 dias de garantia contra defeitos de fabricação.'
    )
  end

  describe 'RF-31: idempotent reindex/retry' do
    it 'does not duplicate chunks/embeddings when triggered twice' do
      described_class.call(source: source, embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider)
      first_ids = source.knowledge_chunks.reload.pluck(:id)

      described_class.call(source: source, embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider)
      second_ids = source.knowledge_chunks.reload.pluck(:id)

      expect(second_ids.length).to eq(first_ids.length)
      expect(first_ids & second_ids).to be_empty # replaced, not appended to
    end

    it 'reflects updated content on subsequent reindex without leaving stale chunks behind' do
      described_class.call(source: source, embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider)

      source.update!(content: 'Nova política: 60 dias de garantia.')
      described_class.call(source: source, embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider)

      contents = source.knowledge_chunks.reload.pluck(:content)
      expect(contents.join).to include('60 dias de garantia')
      expect(contents.join).not_to include('90 dias')
    end
  end
end
