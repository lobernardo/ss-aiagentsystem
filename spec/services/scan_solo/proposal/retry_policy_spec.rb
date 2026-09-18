# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Proposal::RetryPolicy do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end
  let(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
  let(:agent) { create(:user, account: account) }

  describe '.retryable?' do
    it 'is true for a safely-retryable generate failure' do
      version = proposal.versions.create!(status: :failed, failure_reason: 'timeout')

      expect(described_class.retryable?(version)).to be true
    end

    it 'is false for an unsafe failure reason' do
      version = proposal.versions.create!(status: :failed, failure_reason: 'unknown_state')

      expect(described_class.retryable?(version)).to be false
    end

    it 'is false for a non-failed version' do
      version = proposal.versions.create!(status: :generated, value: 1000)

      expect(described_class.retryable?(version)).to be false
    end
  end

  describe '.retry!' do
    it 'retries a retryable generate failure without duplicating the proposal' do
      version = proposal.versions.create!(status: :failed, failure_reason: 'timeout', generate_correlation_id: SecureRandom.uuid)

      expect { described_class.retry!(proposal_version: version) }.not_to change(ScanSolo::Proposal, :count)

      expect(version.reload).to be_generated
      expect(version.value).to eq(ScanSolo::Proposal::MockProvider::DEFAULT_VALUE)
    end

    it 'retries a retryable send failure without duplicating the send' do
      version = proposal.versions.create!(
        status: :failed, failure_reason: 'timeout', value: 1000, currency: 'BRL', artifact_url: 'https://x.test/a.pdf',
        send_correlation_id: SecureRandom.uuid
      )

      expect do
        described_class.retry!(proposal_version: version, conversation: conversation, actor: agent)
      end.to change { conversation.messages.outgoing.count }.by(1)

      expect(version.reload).to be_sent
    end

    it 'raises and leaves the version untouched for an unsafe failure, for manual review' do
      version = proposal.versions.create!(status: :failed, failure_reason: 'unknown_state', generate_correlation_id: SecureRandom.uuid)

      expect { described_class.retry!(proposal_version: version) }.to raise_error(ScanSolo::Proposal::RetryPolicy::UnsafeRetryError)

      expect(version.reload).to be_failed
      expect(version.failure_reason).to eq('unknown_state')
    end
  end
end
