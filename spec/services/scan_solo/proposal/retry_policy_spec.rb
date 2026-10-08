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

      expect(version.reload).to be_awaiting_approval
      expect(version.value).to eq(ScanSolo::Proposal::MockProvider::DEFAULT_VALUE)
    end

    # CT-10 / RF-32: a delivery failure is redelivered by the DeliveryService
    # with the stored PDF; the legacy send retry through Make is gone.
    describe 'delivery failure (CT-10)' do
      let(:artifact_url) { 'https://make.example/proposals/7.pdf' }
      let(:version) do
        proposal.versions.create!(status: :failed, failure_reason: 'template_missing', value: 1000, currency: 'BRL', artifact_url: artifact_url,
                                  generate_correlation_id: SecureRandom.uuid, generate_callback_applied_at: Time.current)
      end
      let(:proposal_messages) { conversation.messages.where("additional_attributes ->> 'scansolo_origin' = 'proposal'") }

      before do
        allow(Resolv).to receive(:getaddresses).and_call_original
        allow(Resolv).to receive(:getaddresses).with('make.example').and_return(['93.184.216.34'])
        stub_request(:get, artifact_url).to_return(status: 200, body: '%PDF-1.4', headers: { 'Content-Type' => 'application/pdf' })
      end

      it 'is retryable whatever the delivery failure reason' do
        expect(described_class.retryable?(version)).to be true
      end

      it 'sends one new proposal message with the same stored blob, without downloading nor calling Make' do
        version.document.attach(io: StringIO.new('%PDF-1.4'), filename: 'SS.pdf', content_type: 'application/pdf')
        blob_id = version.document.blob.id

        expect { described_class.retry!(proposal_version: version, actor: agent) }
          .to change(proposal_messages, :count).by(1).and not_change(ScanSolo::MakeRequest, :count)

        expect(a_request(:get, artifact_url)).not_to have_been_made
        expect(version.reload).to have_attributes(status: 'generated', failure_reason: nil, sent_message: proposal_messages.sole)
        expect(version.document.blob.id).to eq(blob_id)
        expect(ScanSolo::AuditEvent.find_by!(event_type: 'proposal.retry_requested'))
          .to have_attributes(actor: agent, payload: include('operation' => 'delivery'))
      end

      # RF-01: the PDF download moved to ApprovalRequestService (RF-15 c re-downloads it there).
      it 'never downloads the PDF and fails the redelivery when it is missing' do
        described_class.retry!(proposal_version: version, actor: agent)

        expect(a_request(:get, artifact_url)).not_to have_been_made
        expect(version.reload).to have_attributes(status: 'failed', failure_reason: 'artifact_download_failed')
        expect(proposal_messages.count).to eq(0)
      end
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
