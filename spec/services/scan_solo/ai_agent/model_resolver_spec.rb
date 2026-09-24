# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::AiAgent::ModelResolver do
  let(:account) { create(:account) }
  let(:config) { ScanSolo::AiAgentConfig.draft_for!(account) }

  describe '.resolve' do
    it 'resolves through Llm::FeatureRouter using the feature default when no model_selection is set' do
      expect(Llm::FeatureRouter).to receive(:resolve).with(feature: 'scansolo_agent_response', account: account).and_call_original

      result = described_class.resolve(config: config)

      expect(result).to include(
        model: Llm::Models.default_model_for('scansolo_agent_response'),
        source: :default
      )
    end

    it 'prefers the configured model_selection when it is valid for the feature' do
      config.update!(model_selection: 'gpt-4.1')

      result = described_class.resolve(config: config)

      expect(result).to include(model: 'gpt-4.1', provider: 'openai', source: :agent_config)
    end

    it 'fails loudly when a stored model is not available for the feature' do
      config.update!(model_selection: 'not-a-real-model')

      expect { described_class.resolve(config: config) }.to raise_error(ArgumentError, /Unknown ScanSolo model/)
    end

    it 'respects an account-level override, same as any other Llm::FeatureRouter-resolved feature' do
      account.update!(captain_models: { 'scansolo_agent_response' => 'gpt-5.1' })

      result = described_class.resolve(config: config)

      expect(result).to include(model: 'gpt-5.1', source: :account_override)
    end
  end
end
