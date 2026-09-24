# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::AiTurnJob do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:lock_key) { format(described_class::LOCK_KEY, conversation_id: conversation.id) }

  let(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact)
  end

  def publish_enabled_config!
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente ScanSolo', enabled: true, allowed_inbox_ids: [inbox.id])
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

  describe 'RF-09: a re-run after a crash before the send resumes the same turn' do
    before { publish_enabled_config! }

    it 'ends with 1 turn, 1 correlation id and 1 outgoing message' do
      crashing = ->(**) { raise Interrupt }
      expect { described_class.new.perform(message.id, llm_provider: crashing) }.to raise_error(Interrupt)
      crashed_turn = ScanSolo::AiTurn.find_by!(message_id: message.id)
      expect(crashed_turn).to be_pending
      Redis::LockManager.new.unlock(lock_key) # the crashed worker's lock expires with its TTL

      described_class.new.perform(message.id, llm_provider: ScanSolo::TestMode::MockLlmProvider)

      turns = ScanSolo::AiTurn.where(message_id: message.id)
      expect(turns.count).to eq(1)
      expect(turns.sole).to have_attributes(correlation_id: crashed_turn.correlation_id, invocation_status: 'succeeded')
      expect(conversation.messages.outgoing.count).to eq(1)
    end
  end

  describe 'RF-11: per-conversation mutex' do
    before { publish_enabled_config! }

    it 're-enqueues itself without creating a turn while another turn of the conversation holds the lock' do
      Redis::LockManager.new.lock(lock_key, ScanSolo::AI_TURN_LOCK_TTL)

      expect { described_class.perform_now(message.id, llm_provider: 'ScanSolo::TestMode::MockLlmProvider') }
        .to have_enqueued_job(described_class).with(message.id, llm_provider: 'ScanSolo::TestMode::MockLlmProvider')
      expect(ScanSolo::AiTurn.count).to eq(0)
    ensure
      Redis::LockManager.new.unlock(lock_key)
    end

    it 'keeps the lock longer than the bounded model call' do
      expect(ScanSolo::AI_TURN_LOCK_TTL).to be > ScanSolo::AI_TURN_MODEL_TIMEOUT * (ScanSolo::AI_TURN_MODEL_MAX_RETRIES + 1)
    end

    it 'releases the lock after the turn' do
      described_class.new.perform(message.id, llm_provider: ScanSolo::TestMode::MockLlmProvider)

      expect(Redis::LockManager.new.locked?(lock_key)).to be false
    end
  end

  describe 'suppression when no published/enabled AI agent config exists' do
    it 'records a suppressed turn and sends no outbound message' do
      described_class.new.perform(message.id)

      turn = ScanSolo::AiTurn.find_by(message_id: message.id)
      expect(turn).to have_attributes(invocation_status: 'suppressed', failure_reason: 'config_unavailable')
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
