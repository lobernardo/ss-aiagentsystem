# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::AiTurnJob do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  let(:message) do
    create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact)
  end

  def publish_enabled_config!
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente ScanSolo', enabled: true)
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  describe 'RF-35: only runs for an already-persisted native message' do
    it 'is a no-op when the message id does not exist' do
      expect { described_class.new.perform(-1) }.not_to change(ScanSolo::AiTurn, :count)
    end
  end

  describe 'RF-24/RF-36: turn + outbound message dedupe' do
    before { publish_enabled_config! }

    it 'creates exactly one AiTurn and one outbound message when performed once' do
      described_class.new.perform(message.id, llm_provider: ScanSolo::TestMode::MockLlmProvider)

      expect(ScanSolo::AiTurn.where(message_id: message.id).count).to eq(1)
      expect(conversation.messages.outgoing.count).to eq(1)

      turn = ScanSolo::AiTurn.find_by(message_id: message.id)
      expect(turn).to be_succeeded
      expect(turn.correlation_id).to be_present
    end

    it 'produces exactly one AiTurn and one outbound message when performed twice for the same message id (Sidekiq retry)' do
      described_class.new.perform(message.id, llm_provider: ScanSolo::TestMode::MockLlmProvider)
      described_class.new.perform(message.id, llm_provider: ScanSolo::TestMode::MockLlmProvider)

      expect(ScanSolo::AiTurn.where(message_id: message.id).count).to eq(1)
      expect(conversation.messages.outgoing.count).to eq(1)
    end
  end

  describe 'suppression when no published/enabled AI agent config exists' do
    it 'records a suppressed turn and sends no outbound message' do
      described_class.new.perform(message.id)

      turn = ScanSolo::AiTurn.find_by(message_id: message.id)
      expect(turn).to be_suppressed
      expect(turn.failure_reason).to be_present
      expect(conversation.messages.outgoing.count).to eq(0)
    end
  end

  describe 'sent message content' do
    before { publish_enabled_config! }

    it 'is authored by an AgentBot sender, never a parallel message store' do
      described_class.new.perform(message.id, llm_provider: ScanSolo::TestMode::MockLlmProvider)

      outbound = conversation.messages.outgoing.last
      expect(outbound.sender_type).to eq('AgentBot')
      expect(outbound.content).to be_present
    end
  end
end
