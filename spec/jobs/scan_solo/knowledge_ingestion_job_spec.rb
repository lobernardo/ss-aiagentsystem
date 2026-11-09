# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::KnowledgeIngestionJob do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }

  before do
    allow(ScanSolo::Knowledge::EmbeddingService).to receive(:call) do |content:, **|
      ScanSolo::TestMode::MockEmbeddingProvider.call(content: content)
    end
  end

  it 'runs on the low queue' do
    expect(described_class.new.queue_name).to eq('low')
  end

  it 'is enqueued with the source pending on create and indexes it when performed' do
    source = nil
    expect do
      source = ScanSolo::KnowledgeSource.create!(account: account, added_by: user, source_type: :faq, origin: 'manual',
                                                 content: 'Atendemos de segunda a sexta.')
    end.to have_enqueued_job(described_class).on_queue('low')
    expect(source).to be_pending

    perform_enqueued_jobs(only: described_class)

    expect(source.reload).to have_attributes(index_status: 'indexed', chunk_count: 1)
    expect(source.indexed_at).to be_present
  end

  it 'propagates the failed state for a source carrying the internal commercial contact name (RF-22)' do
    source = ScanSolo::KnowledgeSource.create!(account: account, added_by: user, source_type: :faq, origin: 'manual',
                                               content: 'Atendemos de segunda a sexta.')
    perform_enqueued_jobs(only: described_class)
    source.update_columns(content: 'Fale com o Luciano.') # rubocop:disable Rails/SkipsModelValidations

    described_class.perform_now(source.id)

    expect(source.reload).to have_attributes(index_status: 'failed', chunk_count: 0,
                                             index_error: ScanSolo::Knowledge::IngestionService::INTERNAL_NAME_ERROR)
    expect(source.knowledge_chunks).to be_empty
    expect(ScanSolo::Knowledge::EmbeddingService).to have_received(:call).once
  end

  it 'does nothing for a source deleted before it runs' do
    expect { described_class.perform_now(0) }.not_to raise_error
  end
end
