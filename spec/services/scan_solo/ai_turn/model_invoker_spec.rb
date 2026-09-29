# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::AiTurn::ModelInvoker do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:config) { ScanSolo::AiAgentConfig.draft_for!(account) }
  let(:payload) do
    {
      system: 'regras do agente',
      messages: [{ role: 'user', content: 'oi' }, { role: 'assistant', content: 'olá!' }, { role: 'user', content: 'quero preço' }],
      schema: { name: 'scansolo_turn', strict: false, schema: { type: 'object' } }
    }
  end

  describe 'structured output through the injected provider' do
    it 'returns the reply, the requested actions and the measured latency' do
      actions = [{ 'action_id' => 'human_handoff', 'params' => { 'reason' => 'pediu humano' } }]
      provider = ->(**kwargs) { ScanSolo::TestMode::MockLlmProvider.call(**kwargs, fixture_response: 'Olá!', fixture_actions: actions) }

      result = described_class.call(config: config, payload: payload, llm_provider: provider)

      expect(result).not_to be_failed
      expect(result).to have_attributes(content: 'Olá!', actions: actions, provider: 'scansolo_test_mode', model: 'scansolo-mock-llm')
      expect(result.latency_ms).to be >= 0
    end

    it 'raises for output that does not follow the {reply, actions, asked_fields, summary} schema' do
      provider = ->(**) { { content: 'texto solto', provider: 'x', model: 'y' } }

      expect { described_class.call(config: config, payload: payload, llm_provider: provider) }
        .to raise_error(described_class::InvalidOutputError)
    end

    it 'lets a non-provider exception propagate to the orchestrator (RF-07)' do
      provider = ->(**) { raise ArgumentError, 'bug' }

      expect { described_class.call(config: config, payload: payload, llm_provider: provider) }.to raise_error(ArgumentError)
    end
  end

  describe 'RF-10/CT-02: required qualification metadata' do
    let(:base_output) { { 'reply' => 'ok', 'actions' => [] } }

    [
      {},
      { 'summary' => false },
      { 'asked_fields' => [] },
      { 'asked_fields' => [], 'summary' => 'sim' },
      { 'asked_fields' => [], 'summary' => nil },
      { 'asked_fields' => [], 'summary' => 0 },
      { 'asked_fields' => nil, 'summary' => false },
      { 'asked_fields' => 'nome', 'summary' => false },
      { 'asked_fields' => {}, 'summary' => false },
      { 'asked_fields' => ['nome', 1], 'summary' => false }
    ].each do |metadata|
      it "rejects missing or malformed metadata #{metadata.inspect}" do
        output = base_output.merge(metadata)
        provider = ->(**) { { content: output } }

        expect { described_class.call(config: config, payload: payload, llm_provider: provider) }.to(
          raise_error { |error| expect(error.class.name).to eq('ScanSolo::AiTurn::ModelInvoker::InvalidOutputError') }
        )
      end
    end

    it 'returns the supplied asked fields and a true summary indicator' do
      provider = lambda do |**kwargs|
        ScanSolo::TestMode::MockLlmProvider.call(**kwargs, fixture_asked_fields: %w[nome area], fixture_summary: true)
      end

      result = described_class.call(config: config, payload: payload, llm_provider: provider)

      expect(result).to have_attributes(asked_fields: %w[nome area], summary: true)
    end

    it 'accepts an empty asked fields array and a false summary indicator' do
      result = described_class.call(config: config, payload: payload, llm_provider: ScanSolo::TestMode::MockLlmProvider)

      expect(result).to have_attributes(asked_fields: [], summary: false)
    end
  end

  describe 'real provider path (RubyLLM)' do
    let(:reply) do
      instance_double(RubyLLM::Message, content: { 'reply' => 'ok', 'actions' => [], 'asked_fields' => [], 'summary' => false },
                                        input_tokens: 11, output_tokens: 3)
    end
    let(:chat) { instance_double(RubyLLM::Chat) }
    let(:llm_context) { instance_double(RubyLLM::Context) }

    before do
      allow(Llm::Config).to receive(:initialize!)
      allow(ScanSolo::AiAgent::ModelResolver).to receive(:resolve).and_return(provider: 'openai', model: 'gpt-4.1-mini')
      allow(RubyLLM).to receive(:context).and_return(llm_context)
      allow(llm_context).to receive(:chat).with(model: 'gpt-4.1-mini').and_return(chat)
      allow(chat).to receive_messages(with_instructions: chat, with_schema: chat, add_message: nil, ask: reply)
    end

    it 'sends the system message as instructions, the schema and the history as chat messages' do
      result = described_class.call(config: config, payload: payload)

      expect(chat).to have_received(:with_instructions).with('regras do agente')
      expect(chat).to have_received(:with_schema).with(payload[:schema])
      expect(chat).to have_received(:add_message).with(role: :user, content: 'oi')
      expect(chat).to have_received(:add_message).with(role: :assistant, content: 'olá!')
      expect(chat).to have_received(:ask).with('quero preço')
      expect(result).to have_attributes(content: 'ok', provider: 'openai', model: 'gpt-4.1-mini', input_tokens: 11, output_tokens: 3)
    end

    it 'bounds the model call with the ScanSolo timeout and a single retry' do
      llm_config = Struct.new(:request_timeout, :max_retries).new
      allow(RubyLLM).to receive(:context).and_yield(llm_config).and_return(llm_context)

      described_class.call(config: config, payload: payload)

      expect(llm_config.to_h).to eq(request_timeout: ScanSolo::AI_TURN_MODEL_TIMEOUT.to_i, max_retries: ScanSolo::AI_TURN_MODEL_MAX_RETRIES)
    end
  end

  describe 'RF-42: provider failure handling' do
    it 'returns a failure result instead of raising when the provider raises a configuration error' do
      allow(Llm::Config).to receive(:initialize!).and_raise(RubyLLM::ConfigurationError, 'missing openai_api_key')

      result = described_class.call(config: config, payload: payload)

      expect(result).to be_failed
      expect(result.failure_reason).to include('RubyLLM::ConfigurationError')
      expect(result.content).to be_nil
    end

    it 'returns a failure result on a timeout' do
      allow(Llm::Config).to receive(:initialize!).and_raise(Timeout::Error, 'timed out')

      result = described_class.call(config: config, payload: payload)

      expect(result).to be_failed
      expect(result.failure_reason).to include('Timeout::Error')
    end

    it 'redacts secret-shaped values from the failure reason' do
      allow(Llm::Config).to receive(:initialize!).and_raise(RubyLLM::Error, 'bad key sk-live_abcdefghijklmnop')

      expect(described_class.call(config: config, payload: payload).failure_reason).not_to include('sk-live_abcdefghijklmnop')
    end
  end
end
