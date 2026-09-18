# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::KnowledgeChunk do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:source) { ScanSolo::KnowledgeSource.create!(account: account, added_by: user, source_type: :faq, content: 'x', origin: 'manual') }

  describe 'RF-28: pgvector embedding via has_neighbors directly (never through Captain::)' do
    let(:query_vector) { Array.new(1536) { |i| i.even? ? 1.0 : 0.0 } }
    let(:aligned_vector) { Array.new(1536) { |i| i.even? ? 1.0 : 0.0 } }
    let(:orthogonal_vector) { Array.new(1536) { |i| i.even? ? 0.0 : 1.0 } }

    it 'ranks chunks by embedding distance via nearest_neighbors' do
      near = described_class.create!(source: source, content: 'perto', embedding: aligned_vector)
      described_class.create!(source: source, content: 'longe', embedding: orthogonal_vector)

      results = described_class.nearest_neighbors(:embedding, query_vector, distance: 'cosine').first(1)

      expect(results).to eq([near])
    end
  end

  describe 'validations' do
    it 'requires content' do
      chunk = described_class.new(source: source, content: nil)

      expect(chunk).not_to be_valid
      expect(chunk.errors[:content]).to be_present
    end
  end
end
