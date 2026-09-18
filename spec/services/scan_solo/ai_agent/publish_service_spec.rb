# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::AiAgent::PublishService do
  let(:account) { create(:account) }

  describe '#call' do
    it 'creates a new published snapshot copying the current draft fields' do
      draft = ScanSolo::AiAgentConfig.draft_for!(account)
      draft.update!(name: 'Agente v1', enabled: true, model_selection: 'gpt-4.1')

      published = described_class.new(account: account).call

      expect(published).to be_persisted
      expect(published).to be_published
      expect(published.name).to eq('Agente v1')
      expect(published.model_selection).to eq('gpt-4.1')
      expect(ScanSolo::AiAgentConfig.published_for(account)).to eq(published)
    end

    it 'editing the draft after publish never changes the already-published snapshot (RF-22)' do
      draft = ScanSolo::AiAgentConfig.draft_for!(account)
      draft.update!(name: 'Agente v1')
      first_published = described_class.new(account: account).call

      draft.update!(name: 'Agente v2 (rascunho em edicao)')

      expect(first_published.reload.name).to eq('Agente v1')
      expect(ScanSolo::AiAgentConfig.published_for(account).name).to eq('Agente v1')
    end

    it 'atomically swaps the active published version on a second publish' do
      draft = ScanSolo::AiAgentConfig.draft_for!(account)
      draft.update!(name: 'Agente v1')
      first_published = described_class.new(account: account).call

      draft.update!(name: 'Agente v2')
      second_published = described_class.new(account: account).call

      expect(second_published.id).not_to eq(first_published.id)
      expect(ScanSolo::AiAgentConfig.published_for(account)).to eq(second_published)
      # The previous published snapshot is retained as immutable history, not mutated in place.
      expect(first_published.reload.name).to eq('Agente v1')
    end

    it 'creates exactly one new published row per call' do
      ScanSolo::AiAgentConfig.draft_for!(account)

      expect { described_class.new(account: account).call }.to change(ScanSolo::AiAgentConfig, :count).by(1)
    end
  end
end
