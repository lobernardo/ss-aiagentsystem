# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::KnowledgeSource do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }

  describe 'RF-27: one entry of each type persists with source metadata and is listable' do
    %i[document faq company_info].each do |type|
      it "persists a #{type} entry with source metadata (type, origin, added-by, timestamp)" do
        source = described_class.create!(
          account: account,
          added_by: user,
          source_type: type,
          title: "#{type} entry",
          content: 'Conteúdo de exemplo para indexação.',
          origin: 'manual'
        )

        expect(source).to be_persisted
        expect(source.source_type).to eq(type.to_s)
        expect(source.origin).to eq('manual')
        expect(source.added_by).to eq(user)
        expect(source.created_at).to be_present
        expect(described_class.where(account: account)).to include(source)
      end
    end
  end

  describe 'validations' do
    it 'requires origin metadata' do
      source = described_class.new(account: account, added_by: user, source_type: :faq, content: 'x')

      expect(source).not_to be_valid
      expect(source.errors[:origin]).to be_present
    end
  end

  describe 'defaults' do
    it 'is enabled by default' do
      source = described_class.create!(account: account, added_by: user, source_type: :faq, content: 'x', origin: 'manual')

      expect(source.enabled).to be true
    end
  end

  describe '#knowledge_chunks' do
    it 'destroys dependent chunks when the source is destroyed' do
      source = described_class.create!(account: account, added_by: user, source_type: :faq, content: 'x', origin: 'manual')
      chunk = ScanSolo::KnowledgeChunk.create!(source: source, content: 'chunk um')

      source.destroy!

      expect(ScanSolo::KnowledgeChunk.where(id: chunk.id)).not_to exist
    end
  end
end
