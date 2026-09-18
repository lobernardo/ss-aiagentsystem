# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::AiTurn::ModelInvoker do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:config) { ScanSolo::AiAgentConfig.draft_for!(account) }

  describe 'RF-21: resolves through the injected/default provider, never a second hand-rolled client' do
    it 'delegates to the injected llm_provider when given' do
      result = described_class.call(config: config, prompt: 'ola', llm_provider: ScanSolo::TestMode::MockLlmProvider)

      expect(result).not_to be_failed
      expect(result.content).to be_present
      expect(result.provider).to eq(ScanSolo::TestMode::MockLlmProvider::PROVIDER)
    end
  end

  describe 'RF-42: provider failure handling' do
    it 'returns a failure result instead of raising when the provider raises a configuration error' do
      allow(Llm::Config).to receive(:initialize!).and_raise(RubyLLM::ConfigurationError, 'missing openai_api_key')

      result = described_class.call(config: config, prompt: 'ola')

      expect(result).to be_failed
      expect(result.failure_reason).to include('RubyLLM::ConfigurationError')
      expect(result.content).to be_nil
    end

    it 'returns a failure result on a timeout' do
      allow(Llm::Config).to receive(:initialize!).and_raise(Timeout::Error, 'timed out')

      result = described_class.call(config: config, prompt: 'ola')

      expect(result).to be_failed
      expect(result.failure_reason).to include('Timeout::Error')
    end

    it 'never raises past its own boundary for a provider error' do
      allow(Llm::Config).to receive(:initialize!).and_raise(RubyLLM::Error, 'malformed output')

      expect { described_class.call(config: config, prompt: 'ola') }.not_to raise_error
    end
  end

  describe 'RF-42: a provider failure leaves already-persisted history intact and sends nothing' do
    let(:contact) { create(:contact, account: account) }
    let(:conversation) { create(:conversation, account: account, contact: contact) }
    let(:message) do
      create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact)
    end

    before do
      config.update!(name: 'Agente ScanSolo', enabled: true)
      ScanSolo::AiAgent::PublishService.new(account: account).call
      allow(Llm::Config).to receive(:initialize!).and_raise(RubyLLM::ConfigurationError, 'missing openai_api_key')
    end

    it 'records a failed turn, sends zero outbound messages, and preserves prior history' do
      ScanSolo::AiTurnJob.new.perform(message.id)

      turn = ScanSolo::AiTurn.find_by(message_id: message.id)
      expect(turn).to be_failed
      expect(turn.failure_reason).to be_present
      expect(conversation.messages.outgoing.count).to eq(0)
      expect(conversation.messages.incoming.count).to eq(1)
      expect(message.reload).to be_persisted
    end
  end
end
