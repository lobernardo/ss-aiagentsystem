# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::AiTurn::EligibilityGuard do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  describe '.eligible?' do
    it 'is eligible by default (ai_active)' do
      expect(described_class.eligible?(conversation: conversation)).to be true
    end

    %w[handoff_requested awaiting_human human_active paused closed].each do |state|
      it "is not eligible while the conversation is #{state}" do
        ScanSolo::ConversationExtension.resolve_for(conversation).update!(ai_control_state: state)

        expect(described_class.eligible?(conversation: conversation)).to be false
      end
    end
  end

  describe 'RF-37: an inbound message on a human-owned conversation produces zero AI-authored outbound messages' do
    before do
      draft = ScanSolo::AiAgentConfig.draft_for!(account)
      draft.update!(name: 'Agente ScanSolo', enabled: true)
      ScanSolo::AiAgent::PublishService.new(account: account).call

      ScanSolo::ConversationExtension.resolve_for(conversation).update!(ai_control_state: :human_active)
    end

    it 'suppresses the turn and sends no message' do
      message = create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact)

      ScanSolo::AiTurnJob.new.perform(message.id)

      turn = ScanSolo::AiTurn.find_by(message_id: message.id)
      expect(turn).to be_suppressed
      expect(conversation.messages.outgoing.count).to eq(0)
    end
  end
end
