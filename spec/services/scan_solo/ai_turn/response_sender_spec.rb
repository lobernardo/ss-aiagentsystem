# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::AiTurn::ResponseSender do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:message) do
    create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact)
  end
  let(:config) do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente ScanSolo', enabled: true)
    draft
  end
  let(:turn) do
    ScanSolo::AiTurn.create!(message: message, conversation: conversation, correlation_id: SecureRandom.uuid,
                             invocation_status: :pending)
  end
  let(:result) do
    ScanSolo::AiTurn::ModelInvoker::Result.new(content: 'Ola! Como posso ajudar?', provider: 'scansolo_test_mode',
                                               model: 'scansolo-mock-llm', input_tokens: 5, output_tokens: 6)
  end

  describe '.call' do
    it 'persists an outbound Message whose content is identical to the delivered content (RF-43)' do
      outbound = described_class.call(message: message, config: config, result: result, turn: turn)

      expect(outbound).to be_persisted
      expect(outbound.content).to eq(result.content)
      expect(outbound.message_type).to eq('outgoing')
      expect(outbound.sender_type).to eq('AgentBot')
    end

    it 'persists a matching evidence record that references the sent message id' do
      outbound = described_class.call(message: message, config: config, result: result, turn: turn)

      expect(turn.reload.response_message_id).to eq(outbound.id)
      expect(turn.response_message.content).to eq(outbound.content)
    end

    it 'marks the turn succeeded with the model telemetry and action evidence' do
      described_class.call(message: message, config: config, result: result, turn: turn,
                           action_evidence: [{ type: 'stage_transition', target_stage: 'em_qualificacao' }])

      turn.reload
      expect(turn).to be_succeeded
      expect(turn.model_provider).to eq('scansolo_test_mode')
      expect(turn.model_reference).to eq('scansolo-mock-llm')
      expect(turn.input_tokens).to eq(5)
      expect(turn.output_tokens).to eq(6)
      expect(turn.action_evidence).to eq([{ 'type' => 'stage_transition', 'target_stage' => 'em_qualificacao' }])
    end
  end
end
