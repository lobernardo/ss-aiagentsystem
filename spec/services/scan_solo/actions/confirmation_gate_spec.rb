# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Actions::ConfirmationGate do
  describe '.blocked?' do
    it 'blocks a requires_confirmation action with no confirmation recorded' do
      action = ScanSolo::AgentAction.new(classification: :requires_confirmation)

      expect(described_class.blocked?(action: action, confirmed: false)).to be true
    end

    it 'does not block a requires_confirmation action once confirmed' do
      action = ScanSolo::AgentAction.new(classification: :requires_confirmation)

      expect(described_class.blocked?(action: action, confirmed: true)).to be false
    end

    it 'never blocks an automatic action, confirmed or not' do
      action = ScanSolo::AgentAction.new(classification: :automatic)

      expect(described_class.blocked?(action: action, confirmed: false)).to be false
      expect(described_class.blocked?(action: action, confirmed: true)).to be false
    end
  end

  describe 'RF-49: end-to-end gating through the executor' do
    let(:account) { create(:account, scansolo_enabled: true) }
    let(:contact) { create(:contact, account: account) }
    let(:conversation) { create(:conversation, account: account, contact: contact) }
    let(:message) { create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact) }
    let!(:turn) do
      ScanSolo::AiTurn.create!(message: message, conversation: conversation, correlation_id: SecureRandom.uuid)
    end

    before do
      ScanSolo::AgentAction.create!(
        action_id: 'gated_action',
        classification: :requires_confirmation,
        schema: { 'type' => 'object', 'properties' => {}, 'additionalProperties' => false }
      )
    end

    it 'invoking without confirmation stays pending and produces zero side effects' do
      side_effect_called = false
      key = SecureRandom.uuid

      result = ScanSolo::Actions::Executor.call(
        action_id: 'gated_action', params: {}, correlation_id: turn.correlation_id, idempotency_key: key, turn: turn
      ) { |_p| side_effect_called = true }

      expect(result.pending).to be true
      expect(side_effect_called).to be false
      expect(result.execution).to be_pending
      expect(result.execution.audit_event).to be_nil
    end

    it 'a subsequent confirmed invocation with the same idempotency key runs the side effect exactly once' do
      side_effect_calls = 0
      key = SecureRandom.uuid

      ScanSolo::Actions::Executor.call(
        action_id: 'gated_action', params: {}, correlation_id: turn.correlation_id, idempotency_key: key, turn: turn
      ) { |_p| side_effect_calls += 1 }

      result = ScanSolo::Actions::Executor.call(
        action_id: 'gated_action', params: {}, correlation_id: turn.correlation_id, idempotency_key: key, turn: turn,
        confirmed: true
      ) { |_p| side_effect_calls += 1 }

      expect(side_effect_calls).to eq(1)
      expect(result.pending).to be false
      expect(result.execution).to be_executed
    end
  end
end
