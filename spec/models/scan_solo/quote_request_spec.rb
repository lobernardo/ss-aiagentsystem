# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::QuoteRequest do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end
  let(:quote_request) { described_class.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid) }

  it 'exposes the CT-02 status vocabulary' do
    expect(described_class.statuses).to eq('awaiting_reply' => 0, 'correction_requested' => 1, 'replied' => 2)
  end

  it 'starts awaiting the commercial reply' do
    expect(quote_request).to be_awaiting_reply
  end

  it 'requires a correlation id' do
    expect(described_class.new(account: account, opportunity: opportunity)).not_to be_valid
  end

  it 'rejects a second request for the same opportunity through the unique index (RF-15)' do
    quote_request
    duplicate = described_class.new(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid)

    expect { duplicate.save! }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'is open while awaiting reply or correction and closed once replied' do
    expect(quote_request).to be_open

    quote_request.correction_requested!
    expect(quote_request).to be_open

    quote_request.replied!
    expect(quote_request).not_to be_open
  end

  it 'links the opportunity, email conversation and reply message (RF-22)' do
    email_conversation = create(:conversation, account: account)
    reply = create(:message, conversation: email_conversation, account: account)
    quote_request.update!(email_conversation: email_conversation, reply_message: reply)

    reloaded = described_class.find(quote_request.id)

    expect(opportunity.reload.quote_request).to eq(reloaded)
    expect(reloaded.email_conversation).to eq(email_conversation)
    expect(reloaded.reply_message).to eq(reply)
  end
end
