# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::TestMode::MockLlmProvider do
  let(:account) { create(:account) }
  let(:config) { ScanSolo::AiAgentConfig.draft_for!(account) }

  around do |example|
    with_modified_env(OPENAI_API_KEY: nil) { example.run }
  end

  describe '.call' do
    it 'produces a simulated response with zero outbound calls to any real transport' do
      result = described_class.call(config: config, prompt: 'Ola, quero um orcamento')

      expect(result[:content]).to eq(described_class::DEFAULT_RESPONSE)
      expect(result[:real_send]).to be false
    end

    it 'returns the given fixture response instead of the default when one is provided' do
      result = described_class.call(config: config, prompt: 'Ola', fixture_response: 'Resposta fixa de teste')

      expect(result[:content]).to eq('Resposta fixa de teste')
    end

    it 'never resolves to a production provider/model identifier' do
      result = described_class.call(config: config, prompt: 'Ola')

      expect(result[:provider]).to eq('scansolo_test_mode')
      expect(result[:model]).to eq('scansolo-mock-llm')
    end

    it 'runs with no OPENAI_API_KEY set (RF-25)' do
      expect(ENV.fetch('OPENAI_API_KEY', nil)).to be_nil

      expect { described_class.call(config: config, prompt: 'Ola') }.not_to raise_error
    end
  end

  describe '#scansolo_mock_llm_response helper' do
    it 'delegates to the mock provider' do
      result = scansolo_mock_llm_response(config: config, fixture_response: 'via helper')

      expect(result[:content]).to eq('via helper')
      expect(result[:real_send]).to be false
    end
  end
end
