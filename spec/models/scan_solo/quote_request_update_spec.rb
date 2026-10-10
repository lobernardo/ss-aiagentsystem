# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::QuoteRequestUpdate do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end
  let(:quote_request) { ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid) }

  it 'is valid with a version digest and no message yet' do
    expect(described_class.new(account: account, quote_request: quote_request, version_digest: 'abc')).to be_valid
  end

  it 'requires a version digest (RF-14)' do
    update = described_class.new(account: account, quote_request: quote_request)

    expect(update).not_to be_valid
    expect(update.errors[:version_digest]).to be_present
  end

  it 'rejects a second update for the same request and version (RF-14 (c))' do
    described_class.create!(account: account, quote_request: quote_request, version_digest: 'abc')
    duplicate = described_class.new(account: account, quote_request: quote_request, version_digest: 'abc')

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:version_digest]).to be_present
  end

  it 'accepts the same version digest on another request' do
    other_contact = create(:contact, account: account)
    other_opportunity = ScanSolo::PipelineOpportunity.create!(
      account: account, contact: other_contact, conversation: create(:conversation, account: account, contact: other_contact),
      stage: :qualificado
    )
    other_request = ScanSolo::QuoteRequest.create!(account: account, opportunity: other_opportunity, correlation_id: SecureRandom.uuid)
    described_class.create!(account: account, quote_request: quote_request, version_digest: 'abc')

    expect(described_class.new(account: account, quote_request: other_request, version_digest: 'abc')).to be_valid
  end

  it 'links the sent message' do
    message = create(:message, conversation: conversation, account: account)
    update = described_class.create!(account: account, quote_request: quote_request, version_digest: 'abc', message: message)

    expect(update.reload.message).to eq(message)
  end
end
