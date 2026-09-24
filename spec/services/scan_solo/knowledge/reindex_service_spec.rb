# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Knowledge::ReindexService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:source) do
    ScanSolo::KnowledgeSource.create!(
      account: account, added_by: user, source_type: :document, origin: 'upload',
      content: 'Política de garantia: produtos têm 90 dias de garantia contra defeitos de fabricação.'
    )
  end

  before do
    allow(ScanSolo::Knowledge::EmbeddingService).to receive(:call) do |content:, **|
      ScanSolo::TestMode::MockEmbeddingProvider.call(content: content)
    end
  end

  describe 'RF-31/RF-44: reindex through the ingestion job' do
    it 'marks the source pending, clears the previous error and enqueues the ingestion job' do
      source.update_columns(index_status: :failed, index_error: 'erro anterior') # rubocop:disable Rails/SkipsModelValidations

      expect { described_class.call(source: source, actor: user) }.to have_enqueued_job(ScanSolo::KnowledgeIngestionJob).with(source.id)

      expect(source.reload).to have_attributes(index_status: 'pending', index_error: nil)
    end

    it 'records one knowledge_source.reindexed audit event with the actor (RF-50)' do
      expect { described_class.call(source: source, actor: user) }.to change(ScanSolo::AuditEvent, :count).by(1)

      expect(ScanSolo::AuditEvent.last).to have_attributes(event_type: 'knowledge_source.reindexed', subject: source, actor: user)
    end

    it 'does not duplicate chunks when triggered twice' do
      perform_enqueued_jobs(only: ScanSolo::KnowledgeIngestionJob) { described_class.call(source: source, actor: user) }
      first_ids = source.knowledge_chunks.reload.pluck(:id)

      perform_enqueued_jobs(only: ScanSolo::KnowledgeIngestionJob) { described_class.call(source: source, actor: user) }
      second_ids = source.knowledge_chunks.reload.pluck(:id)

      expect(second_ids.length).to eq(first_ids.length)
      expect(first_ids & second_ids).to be_empty # replaced, not appended to
    end
  end
end
