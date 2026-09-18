# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Actions::Executor do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:message) { create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact) }

  let!(:turn) do
    ScanSolo::AiTurn.create!(message: message, conversation: conversation, correlation_id: SecureRandom.uuid)
  end

  before do
    ScanSolo::AgentAction.create!(
      action_id: 'test_action',
      classification: :automatic,
      schema: {
        'type' => 'object',
        'properties' => { 'note' => { 'type' => 'string' } },
        'required' => ['note'],
        'additionalProperties' => false
      }
    )
  end

  def call(params:, idempotency_key: SecureRandom.uuid, confirmed: false, &side_effect)
    described_class.call(
      action_id: 'test_action',
      params: params,
      correlation_id: turn.correlation_id,
      idempotency_key: idempotency_key,
      turn: turn,
      confirmed: confirmed,
      &(side_effect || ->(_p) { 'executed' })
    )
  end

  describe 'CT-04 / RF-47: schema-validated structured parameters only' do
    it 'accepts a registered action id plus a parameter that matches the declared schema' do
      result = call(params: { note: 'ok' })

      expect(result.pending).to be false
      expect(result.execution).to be_executed
    end

    it 'rejects a free-form URL/command/SQL parameter not declared in the schema, before any execution' do
      side_effect_called = false

      expect do
        call(params: { note: 'ok', url: 'http://evil.example.com', command: 'rm -rf /' }) do |_p|
          side_effect_called = true
        end
      end.to raise_error(described_class::InvalidParamsError)

      expect(side_effect_called).to be false
      expect(ScanSolo::AgentActionExecution.count).to eq(0)
    end

    it 'rejects an invocation for an unregistered action id' do
      expect do
        described_class.call(
          action_id: 'does_not_exist', params: {}, correlation_id: turn.correlation_id, idempotency_key: SecureRandom.uuid
        ) { |_p| 'noop' }
      end.to raise_error(described_class::UnregisteredActionError)
    end

    it 'rejects an invocation for a disabled action' do
      ScanSolo::AgentAction.create!(action_id: 'disabled_action', classification: :disabled, schema: { 'type' => 'object' })

      expect do
        described_class.call(
          action_id: 'disabled_action', params: {}, correlation_id: turn.correlation_id, idempotency_key: SecureRandom.uuid
        ) { |_p| 'noop' }
      end.to raise_error(described_class::UnregisteredActionError)
    end
  end

  describe 'RNF-01: idempotency' do
    it 'produces the side effect exactly once when invoked twice with the same idempotency key' do
      call_count = 0
      key = SecureRandom.uuid

      2.times do
        call(params: { note: 'ok' }, idempotency_key: key) { |_p| call_count += 1 }
      end

      expect(call_count).to eq(1)
      expect(ScanSolo::AgentActionExecution.where(idempotency_key: key).count).to eq(1)
    end
  end

  describe 'RF-46: audit trail linked to the originating turn correlation id' do
    it 'creates an audit event referencing the correlation id' do
      result = call(params: { note: 'ok' })

      audit_event = result.execution.audit_event
      expect(audit_event).to be_present
      expect(audit_event.correlation_id).to eq(turn.correlation_id)
      expect(audit_event.subject).to eq(result.execution)
    end
  end

  describe 'a failing side effect' do
    it 'marks the execution failed and does not create an audit event' do
      expect do
        call(params: { note: 'ok' }) { |_p| raise 'boom' }
      end.to raise_error('boom')

      execution = ScanSolo::AgentActionExecution.last
      expect(execution).to be_failed
      expect(execution.audit_event).to be_nil
    end
  end
end
