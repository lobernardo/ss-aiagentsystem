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

      # RF-41: `sent` only after the native message is accepted.
      expect(version.reload).not_to be_sent
      ScanSolo::Messaging::DeliveryReconciler.call(message: version.sent_message)
      expect(version.reload).to be_sent
    end

    describe 'RF-40: retry count, dead letter and reprocess' do
      let(:correlation_id) { SecureRandom.uuid }
      let(:version) do
        proposal.versions.create!(status: :failed, failure_reason: 'provider_unavailable', generate_correlation_id: correlation_id)
      end
      let(:make_provider) { ScanSolo::Proposal::MakeProvider }
      let(:scenario_url) { 'https://hook.make.example/scenario-webhook' }

      before do
        allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :scenario_url).and_return(scenario_url)
        allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :secret).and_return('make-secret')
        stub_request(:post, scenario_url).to_return(status: 503)
        ScanSolo::MakeRequest.create!(account: account, correlation_id: correlation_id, idempotency_key: correlation_id,
                                      action: 'proposal.generate', payload: { proposal_version_id: version.id }, status: :failed)
      end

      def retry_version(confirm_reprocess: false)
        described_class.retry!(proposal_version: version.reload, provider: make_provider, confirm_reprocess: confirm_reprocess, actor: agent)
      end

      it 'uses a new correlation id and increments the operation retry count on each retry' do
        retry_version

        expect(version.reload.generate_correlation_id).not_to eq(correlation_id)
        expect(version.make_request.retry_count).to eq(1)
        expect(version).to have_attributes(status: 'failed', failure_reason: 'provider_unavailable')
      end

      it 'dead-letters the operation after 3 failed retries and then requires a reprocess confirmation' do
        3.times { retry_version }

        expect(version.reload.make_request).to be_dead_letter
        expect(ScanSolo::Make::DeadLetterQuery.call(account: account)).to contain_exactly(version.make_request)
        expect { retry_version }.to raise_error(described_class::ReprocessConfirmationRequiredError)
        expect(ScanSolo::MakeRequest.count).to eq(4)
      end

      it 'reprocesses a dead letter with confirmation through a new MakeRequest' do
        3.times { retry_version }
        stub_request(:post, scenario_url).to_return(status: 200)

        expect { retry_version(confirm_reprocess: true) }.to change(ScanSolo::MakeRequest, :count).by(1)

        expect(version.reload.make_request).to have_attributes(status: 'sent', retry_count: 4)
        expect(version).to be_generating
        expect(ScanSolo::Make::DeadLetterQuery.call(account: account)).to be_empty
      end
    end

    it 'raises and leaves the version untouched for an unsafe failure, for manual review' do
      version = proposal.versions.create!(status: :failed, failure_reason: 'unknown_state', generate_correlation_id: SecureRandom.uuid)

      expect { described_class.retry!(proposal_version: version) }.to raise_error(ScanSolo::Proposal::RetryPolicy::UnsafeRetryError)

      expect(version.reload).to be_failed
      expect(version.failure_reason).to eq('unknown_state')
    end
  end
end
