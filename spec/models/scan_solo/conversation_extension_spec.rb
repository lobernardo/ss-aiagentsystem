# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::ConversationExtension do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }

  describe '.resolve_for' do
    it 'creates and returns an extension defaulting to ai_active when none exists' do
      extension = nil

      expect { extension = described_class.resolve_for(conversation) }.to change(described_class, :count).by(1)

      expect(extension.conversation).to eq(conversation)
      expect(extension).to be_ai_active
    end

    it 'returns the existing extension without creating a duplicate' do
      existing = described_class.create!(conversation: conversation, ai_control_state: :human_active)

      expect do
        resolved = described_class.resolve_for(conversation)
        expect(resolved).to eq(existing)
      end.not_to change(described_class, :count)
    end
  end

  describe 'ai_control_state enum transitions' do
    subject(:extension) { described_class.resolve_for(conversation) }

    it 'transitions to ai_active' do
      extension.update!(ai_control_state: :handoff_requested)
      extension.ai_active!
      expect(extension.reload).to be_ai_active
    end

    it 'transitions to handoff_requested' do
      extension.handoff_requested!
      expect(extension.reload).to be_handoff_requested
    end

    it 'transitions to awaiting_human' do
      extension.awaiting_human!
      expect(extension.reload).to be_awaiting_human
    end

    it 'transitions to human_active' do
      extension.human_active!
      expect(extension.reload).to be_human_active
    end

    it 'transitions to paused' do
      extension.paused!
      expect(extension.reload).to be_paused
    end

    it 'transitions to closed' do
      extension.closed!
      expect(extension.reload).to be_closed
    end
  end

  it 'rejects a second extension for the same conversation' do
    described_class.create!(conversation: conversation)
    duplicate = described_class.new(conversation: conversation)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:conversation_id]).to be_present
  end
end
