# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::AiTurn::TurnOrchestrator do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:message) do
    create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact)
  end

  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation,
                                          stage: :em_qualificacao)
  end

  before do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente ScanSolo', enabled: true)
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  describe 'RF-44: a registered action result is visible no later than the outbound message being queued' do
    it 'applies the requested stage transition in the same transaction as the outbound send' do
      described_class.call(
        message: message,
        llm_provider: ScanSolo::TestMode::MockLlmProvider,
        actions: [{ type: 'stage_transition', params: { target_stage: 'qualificado', authorized: true } }]
      )

      expect(opportunity.reload.stage).to eq('qualificado')
      expect(conversation.messages.outgoing.count).to eq(1)

      turn = ScanSolo::AiTurn.find_by(message_id: message.id)
      expect(turn).to be_succeeded
      expect(turn.action_evidence).not_to be_empty
    end

    it 'rolls back the action together with the send when the send fails' do
      allow(ScanSolo::AiTurn::ResponseSender).to receive(:call).and_raise(ActiveRecord::RecordInvalid, opportunity)

      expect do
        described_class.call(
          message: message,
          llm_provider: ScanSolo::TestMode::MockLlmProvider,
          actions: [{ type: 'stage_transition', params: { target_stage: 'qualificado', authorized: true } }]
        )
      end.to raise_error(ActiveRecord::RecordInvalid)

      expect(opportunity.reload.stage).to eq('em_qualificacao')
    end

    it 'is a no-op for actions when no pipeline opportunity exists for the conversation' do
      other_conversation = create(:conversation, account: account, contact: contact)
      other_message = create(:message, account: account, conversation: other_conversation,
                                       message_type: :incoming, sender: contact)

      expect do
        described_class.call(
          message: other_message,
          llm_provider: ScanSolo::TestMode::MockLlmProvider,
          actions: [{ type: 'stage_transition', params: { target_stage: 'qualificado', authorized: true } }]
        )
      end.not_to raise_error

      expect(other_conversation.messages.outgoing.count).to eq(1)
    end
  end

  describe 'without any actions, the canonical guarded turn still runs end to end' do
    it 'creates one turn and sends one outbound message' do
      described_class.call(message: message, llm_provider: ScanSolo::TestMode::MockLlmProvider)

      expect(ScanSolo::AiTurn.where(message_id: message.id).count).to eq(1)
      expect(conversation.messages.outgoing.count).to eq(1)
    end
  end
end
