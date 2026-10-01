# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::QuoteReply do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, conversation: conversation, account: account, message_type: :incoming) }

  it 'exposes the CT-08 kinds and statuses' do
    expect(described_class.kinds).to eq('unmatched' => 0, 'late_reply' => 1)
    expect(described_class.statuses).to eq('pending' => 0, 'linked' => 1, 'discarded' => 2)
  end

  it 'starts pending without a quote request' do
    reply = described_class.create!(account: account, message: message, conversation_id: conversation.id, kind: :unmatched)

    expect(reply).to be_pending
    expect(reply.quote_request).to be_nil
  end

  it 'rejects a second entry for the same message through the unique index' do
    described_class.create!(account: account, message: message, conversation_id: conversation.id, kind: :unmatched)
    duplicate = described_class.new(account: account, message: message, conversation_id: conversation.id, kind: :late_reply)

    expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
