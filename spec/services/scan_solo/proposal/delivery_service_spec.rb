# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Proposal::DeliveryService do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end
  let(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
  let(:correlation_id) { SecureRandom.uuid }
  let(:version) { proposal.versions.create!(generate_correlation_id: correlation_id) }
  let(:artifact_url) { 'https://make.example/proposals/7.pdf' }
  let(:transaction_open_at) { [] }
  let(:proposal_messages) { conversation.messages.where("additional_attributes ->> 'scansolo_origin' = 'proposal'") }
  let(:follow_ups) { conversation.messages.where("additional_attributes ->> 'scansolo_origin' = 'proposal_follow_up'") }

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('make.example').and_return(['93.184.216.34'])
    stub_request(:get, artifact_url).to_return do
      transaction_open_at << [:download, ActiveRecord::Base.connection.current_transaction.joinable?]
      { status: 200, body: '%PDF-1.4 proposta', headers: { 'Content-Type' => 'application/pdf' } }
    end
    allow(ScanSolo::Messaging::NativeTemplateSender).to receive(:call).and_wrap_original do |original, **kwargs|
      transaction_open_at << [:message, ActiveRecord::Base.connection.current_transaction.joinable?]
      original.call(**kwargs)
    end
  end

  def apply_callback
    perform_enqueued_jobs(only: ScanSolo::ProposalDeliveryJob) do
      ScanSolo::Proposal::CallbackHandler.apply_generate_result!(
        proposal_version: version, correlation_id: correlation_id, success: true, value: 12_500, currency: 'BRL',
        artifact_url: artifact_url, valid_until: '2026-11-04T00:00:00Z'
      )
    end
    version.reload
  end

  it 'stores the PDF and sends one proposal template with the stored document in the header (RF-29)' do
    apply_callback

    expect(version.document).to be_attached
    expect(version.document.blob.content_type).to eq('application/pdf')
    expect(version.document.blob.filename.to_s).to eq("#{version.proposal_number}.pdf")
    message = proposal_messages.sole
    expect(version.sent_message_id).to eq(message.id)
    header = message.additional_attributes.dig('template_params', 'processed_params', 'header')
    expect(header).to eq('media_url' => version.document_url, 'media_type' => 'document', 'media_name' => "#{version.proposal_number}.pdf")
    expect(header['media_url']).not_to eq(artifact_url)
    expect(message.additional_attributes['template_params']).to include('name' => 'scansolo_proposal_send')
  end

  it 'needs no approval nor Make send, even with the approval toggle on (RF-28)' do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente', enabled: true, allowed_inbox_ids: [inbox.id], require_proposal_approval: true)
    ScanSolo::AiAgent::PublishService.new(account: account).call
    allow(ScanSolo::Proposal::ApproveService).to receive(:call)

    apply_callback

    expect(proposal_messages.count).to eq(1)
    expect(ScanSolo::MakeRequest.where(action: 'proposal.send').count).to eq(0)
    expect(ScanSolo::Proposal::ApproveService).not_to have_received(:call)
    expect(version).to have_attributes(status: 'generated', approved_at: nil)
  end

  it 'downloads and creates the message outside any open transaction (RNF-01)' do
    apply_callback

    expect(transaction_open_at).to eq([[:download, false], [:message, false]])
  end

  it 'keeps the stage and enrollments untouched while the version is only generated (RF-33)' do
    apply_callback

    expect(opportunity.reload).to be_qualificado
    expect(opportunity.cadence_enrollments).to be_none
  end

  it 'sends one message for two delivery jobs (RNF-02)' do
    apply_callback

    Array.new(2) { Thread.new { ScanSolo::ProposalDeliveryJob.perform_now(version.id) } }.each(&:join)

    expect(proposal_messages.count).to eq(1)
  end

  context 'when the download fails (RF-32)' do
    [
      { status: 500, body: 'error', headers: { 'Content-Type' => 'text/plain' } },
      { status: 200, body: '<html></html>', headers: { 'Content-Type' => 'text/html' } }
    ].each do |reply|
      it "fails the version as artifact_download_failed on HTTP #{reply[:status]} #{reply.dig(:headers, 'Content-Type')}" do
        stub_request(:get, artifact_url).to_return(reply)

        apply_callback

        expect(version).to have_attributes(status: 'failed', failure_reason: 'artifact_download_failed', value: 12_500,
                                           artifact_url: artifact_url)
        expect(version.document).not_to be_attached
        expect(proposal_messages.count).to eq(0)
        expect(ScanSolo::AuditEvent.where(event_type: 'proposal.delivery_failed', subject: opportunity).sole.payload)
          .to include('reason' => 'artifact_download_failed')
        expect(opportunity.reload).to be_qualificado
      end
    end
  end

  context 'with an unavailable WhatsApp proposal template (RF-32)' do
    let(:channel) { create(:channel_whatsapp, account: account, sync_templates: false, message_templates: []) }
    let(:inbox) { channel.inbox }
    let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511944443333') }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }

    before { stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook') }

    it 'fails the version with the guard reason, keeps the PDF and sends nothing' do
      apply_callback

      expect(version).to have_attributes(status: 'failed', failure_reason: 'template_missing', artifact_url: artifact_url)
      expect(version.document).to be_attached
      expect(proposal_messages.count).to eq(0)
      expect(follow_ups.count).to eq(0)
      expect(ScanSolo::AuditEvent.where(event_type: 'proposal.delivery_failed').sole.payload).to include('reason' => 'template_missing')
      expect(opportunity.reload).to be_qualificado
    end
  end
end
