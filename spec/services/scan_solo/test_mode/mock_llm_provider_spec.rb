# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::TestMode::MockLlmProvider do
  let(:account) { create(:account) }
  let(:config) { ScanSolo::AiAgentConfig.draft_for!(account) }

  around do |example|
    with_modified_env(OPENAI_API_KEY: nil) { example.run }
  end

  describe '.call' do
    let(:payload) { { system: 'regras', messages: [{ role: 'user', content: 'Ola, quero um orcamento' }] } }

    it 'produces a simulated structured response with zero outbound calls to any real transport' do
      result = described_class.call(config: config, payload: payload)

      expect(result[:content]).to eq('reply' => described_class::DEFAULT_RESPONSE, 'actions' => [])
      expect(result[:real_send]).to be false
    end

    it 'returns the given fixture reply and actions instead of the default when provided' do
      actions = [{ 'action_id' => 'cadence_signal', 'params' => { 'signal' => 'opt_out' } }]
      result = described_class.call(config: config, payload: payload, fixture_response: 'Resposta fixa de teste', fixture_actions: actions)

      expect(result[:content]).to eq('reply' => 'Resposta fixa de teste', 'actions' => actions)
    end

    it 'captures the last payload it received' do
      described_class.call(config: config, payload: payload)

      expect(described_class.last_payload).to eq(payload)
    end

    it 'never resolves to a production provider/model identifier' do
      result = described_class.call(config: config, payload: payload)

      expect(result[:provider]).to eq('scansolo_test_mode')
      expect(result[:model]).to eq('scansolo-mock-llm')
    end

    it 'runs with no OPENAI_API_KEY set (RF-25)' do
      expect(ENV.fetch('OPENAI_API_KEY', nil)).to be_nil

      expect { described_class.call(config: config, payload: payload) }.not_to raise_error
    end
  end

  describe '#scansolo_mock_llm_response helper' do
    it 'delegates to the mock provider' do
      result = scansolo_mock_llm_response(config: config, fixture_response: 'via helper')

      expect(result[:content]['reply']).to eq('via helper')
      expect(result[:real_send]).to be false
    end
  end
end
