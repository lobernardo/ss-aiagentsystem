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
    # RF-15 (a) replaces OC/RF-32 / CT-10: a delivery failure is redelivered by e-mail through the
    # DeliveryService with the stored PDF; the legacy WhatsApp redelivery is gone.
    describe 'e-mail delivery failure (RF-15 a)' do
      let(:artifact_url) { 'https://make.example/proposals/7.pdf' }
      let(:email_inbox) { create(:channel_email, account: account, email: 'atendimento.comercial@scansolo.com.br').inbox }
      let(:version) do
        proposal.versions.create!(status: :failed, failure_reason: 'email_delivery_failed', value: 1000, currency: 'BRL', artifact_url: artifact_url,
                                  generate_correlation_id: SecureRandom.uuid, generate_callback_applied_at: Time.current,
                                  approved_at: Time.current, approved_by: agent)
      end
      let(:proposal_emails) { Message.where(inbox: email_inbox).outgoing }
      let(:notices) { conversation.messages.where("additional_attributes ->> 'scansolo_origin' = 'proposal_notice'") }

      before do
        contact.update!(email: 'ana@solar.example')
        ScanSolo::AiAgentConfig.draft_for!(account).update!(name: 'Agente', enabled: true, allowed_inbox_ids: [conversation.inbox_id],
                                                            quote_inbox_id: email_inbox.id)
        ScanSolo::AiAgent::PublishService.new(account: account).call
        allow(Resolv).to receive(:getaddresses).and_call_original
        allow(Resolv).to receive(:getaddresses).with('make.example').and_return(['93.184.216.34'])
        stub_request(:get, artifact_url).to_return(status: 200, body: '%PDF-1.4', headers: { 'Content-Type' => 'application/pdf' })
      end

      def attach_document
        version.document.attach(io: StringIO.new('%PDF-1.4'), filename: 'SS.pdf', content_type: 'application/pdf')
        version.document.blob.id
      end

      def confirm_email!
        message = version.reload.sent_message
        message.update!(source_id: '<redelivery@scansolo.example>')
        ScanSolo::Messaging::DeliveryReconciler.call(message: message)
      end

      it 'is retryable whatever the delivery failure reason' do
        version.update!(failure_reason: 'SMTP 550 mailbox unavailable')

        expect(described_class.retryable?(version)).to be true
      end

      it 'sends one new e-mail with the same blob, 0 notices, 0 downloads and 0 Make requests when a notice was accepted' do
        blob_id = attach_document
        accepted_notice = create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :outgoing,
                                           status: :sent, additional_attributes: { 'scansolo_origin' => 'proposal_notice' })
        version.update!(notice_message: accepted_notice)

        expect { described_class.retry!(proposal_version: version, actor: agent) }
          .to change(proposal_emails, :count).by(1).and not_change(ScanSolo::MakeRequest, :count).and not_change(ScanSolo::ProposalVersion, :count)
        confirm_email!

        expect(a_request(:get, artifact_url)).not_to have_been_made
        expect(version.reload).to have_attributes(status: 'sent', sent_message: proposal_emails.sole, notice_message: accepted_notice)
        expect(proposal_emails.sole.attachments.sole.file.blob.checksum).to eq(ActiveStorage::Blob.find(blob_id).checksum)
        expect(version.document.blob.id).to eq(blob_id)
        expect(notices.count).to eq(1)
        expect(ScanSolo::AuditEvent.find_by!(event_type: 'proposal.retry_requested'))
          .to have_attributes(actor: agent, payload: include('operation' => 'email_delivery'))
      end

      it 'sends 0 notices until the new e-mail gets its source_id and 1 after, without an accepted notice' do
        attach_document

        described_class.retry!(proposal_version: version, actor: agent)

        expect(version.reload).to have_attributes(status: 'approved', failure_reason: nil, sent_message: proposal_emails.sole)
        expect(notices.count).to eq(0)

        confirm_email!

        expect(version.reload).to have_attributes(status: 'sent', notice_message: notices.sole)
      end

      # RF-01: the PDF download moved to ApprovalRequestService (RF-15 c re-downloads it there).
      it 'never downloads the PDF and fails the redelivery when it is missing' do
        described_class.retry!(proposal_version: version, actor: agent)

        expect(a_request(:get, artifact_url)).not_to have_been_made
        expect(version.reload).to have_attributes(status: 'failed', failure_reason: 'email_delivery_failed')
        expect(proposal_emails.count).to eq(0)
      end
    end

    describe 'PDF download failure (RF-15 c)' do
      let(:artifact_url) { 'https://make.example/proposals/7.pdf' }
      let(:email_inbox) { create(:channel_email, account: account, email: 'atendimento.comercial@scansolo.com.br').inbox }
      let(:quote_thread) do
        ScanSolo::Quote::EmailThread.open!(inbox: email_inbox, recipient: 'comercial@scansolo.com.br', subject: 'Solicitação de orçamento',
                                           marker: 'quote_request')
      end
      let(:quote_request) do
        ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid, status: :replied,
                                       email_conversation: quote_thread, commercial: { 'total_value' => '1000.00' })
      end
      let(:version) do
        proposal.versions.create!(status: :failed, failure_reason: 'artifact_download_failed', quote_request: quote_request, value: 1000,
                                  currency: 'BRL', artifact_url: artifact_url, generate_correlation_id: SecureRandom.uuid,
                                  generate_callback_applied_at: Time.current)
      end

      before do
        ScanSolo::AiAgentConfig.draft_for!(account).update!(name: 'Agente', enabled: true, allowed_inbox_ids: [conversation.inbox_id],
                                                            quote_inbox_id: email_inbox.id)
        ScanSolo::AiAgent::PublishService.new(account: account).call
        allow(Resolv).to receive(:getaddresses).and_call_original
        allow(Resolv).to receive(:getaddresses).with('make.example').and_return(['93.184.216.34'])
        stub_request(:get, artifact_url).to_return(status: 200, body: '%PDF-1.4', headers: { 'Content-Type' => 'application/pdf' })
      end

      it 'downloads the PDF again, returns to awaiting_approval and requests the approval, without calling Make' do
        version

        expect { described_class.retry!(proposal_version: version, actor: agent) }
          .to not_change(ScanSolo::MakeRequest, :count).and not_change(ScanSolo::ProposalVersion, :count)

        expect(a_request(:get, artifact_url)).to have_been_made.once
        expect(version.reload).to have_attributes(status: 'awaiting_approval', failure_reason: nil, approval_request_message: be_present)
        expect(version.document).to be_attached
        expect(quote_thread.messages.outgoing.count).to eq(1)
        expect(ScanSolo::AuditEvent.find_by!(event_type: 'proposal.retry_requested'))
          .to have_attributes(actor: agent, correlation_id: quote_request.correlation_id, payload: include('operation' => 'artifact_download'))
      end

      it 'is retryable for a checksum mismatch too' do
        version.update!(failure_reason: 'artifact_checksum_mismatch')

        expect(described_class.retryable?(version)).to be true
      end
    end

    describe 'generate failure (RF-15 b, RF-40): retry count, dead letter and reprocess' do
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

      it 'regenerates a timeout on the same version through 1 new Make request' do
        version.update!(failure_reason: 'timeout')
        stub_request(:post, scenario_url).to_return(status: 200)

        expect { retry_version }.to change(ScanSolo::MakeRequest, :count).by(1).and not_change(ScanSolo::ProposalVersion, :count)

        expect(version.reload).to have_attributes(status: 'generating', failure_reason: nil)
        expect(ScanSolo::AuditEvent.find_by!(event_type: 'proposal.retry_requested').payload).to include('operation' => 'generate')
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
