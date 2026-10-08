# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Proposal::MockProvider do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end
  let(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }

  describe '.request_generation' do
    it 'applies a successful generate result with no real HTTP call and no production credential' do
      version = proposal.versions.create!(generate_correlation_id: SecureRandom.uuid)

      described_class.request_generation(proposal_version: version, correlation_id: version.generate_correlation_id)

      expect(version.reload).to be_awaiting_approval
      expect(version.value).to eq(described_class::DEFAULT_VALUE)
      expect(version.artifact_url).to be_present
    end

    it 'applies a failed result when outcome: :failure is requested' do
      version = proposal.versions.create!(generate_correlation_id: SecureRandom.uuid)

      described_class.request_generation(proposal_version: version, correlation_id: version.generate_correlation_id, outcome: :failure)

      expect(version.reload).to be_failed
      expect(version.value).to be_nil
    end
  end

  it 'makes zero real HTTP requests (webmock enforced)' do
    expect(WebMock.net_connect_allowed?).to be false
  end
end
