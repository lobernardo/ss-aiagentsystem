# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Proposal::ApprovalRequestService do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:customer_inbox) { create(:inbox, account: account) }
  let(:email_inbox) { create(:channel_email, account: account, email: 'atendimento.comercial@scansolo.com.br').inbox }
  let(:contact) { create(:contact, account: account, name: 'Ana Souza', email: 'ana@solar.example') }
  let(:conversation) { create(:conversation, account: account, inbox: customer_inbox, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end
  let(:email_conversation) do
    ScanSolo::Quote::EmailThread.open!(inbox: email_inbox, recipient: 'comercial@scansolo.com.br', subject: 'Solicitação de orçamento',
                                       marker: 'quote_request')
  end
  let(:quote_request) do
    ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid, status: :replied,
                                   email_conversation: email_conversation, commercial: { 'total_value' => '12500.00' })
  end
  let(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
  let(:pdf_body) { '%PDF-1.4 proposta' }
  let(:artifact_url) { 'https://make.example/proposals/7.pdf' }
  let(:artifact_sha256) { nil }
  let(:version) do
    proposal.versions.create!(status: :awaiting_approval, quote_request: quote_request, value: 12_500, currency: 'BRL',
                              artifact_url: artifact_url, artifact_sha256: artifact_sha256, generate_correlation_id: SecureRandom.uuid)
  end

  before do
    ScanSolo::AiAgentConfig.draft_for!(account).update!(name: 'Agente', enabled: true, allowed_inbox_ids: [customer_inbox.id],
                                                        quote_inbox_id: email_inbox.id, quote_recipient_email: 'luciano@scansolo.com.br')
    ScanSolo::AiAgent::PublishService.new(account: account).call
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('make.example').and_return(['93.184.216.34'])
    stub_request(:get, artifact_url).to_return(status: 200, body: pdf_body, headers: { 'Content-Type' => 'application/pdf' })
  end

  def audits(event_type)
    ScanSolo::AuditEvent.where(event_type: event_type)
  end

  def run_service(**)
    described_class.call(proposal_version: version, **)
    version.reload
  end

  it 'stores the PDF and posts one approval request on the quote thread to the published recipient (RF-01, RF-02, CT-05)' do
    expect { run_service }.to change(email_conversation.messages.outgoing, :count).by(1)

    expect(version.document.blob).to have_attributes(content_type: 'application/pdf',
                                                     filename: have_attributes(to_s: "#{version.proposal_number}.pdf"))
    message = email_conversation.messages.outgoing.sole
    expect(version).to have_attributes(status: 'awaiting_approval', approval_request_message_id: message.id, approval_requested_at: be_present)
    expect(message.content_attributes['to_emails']).to eq(['luciano@scansolo.com.br'])
    expect(message.attachments.sole.file.filename.to_s).to eq("#{version.proposal_number}.pdf")
    expect(conversation.messages.count).to eq(0)
  end

  it 'carries the proposal number and the Proposals link and audits the request with the quote correlation id (RF-02, RNF-06)' do
    run_service

    message = email_conversation.messages.outgoing.sole
    expect(message.content).to include(version.proposal_number, "/app/accounts/#{account.id}/scansolo/proposals")
    expect(message.content).not_to include('falta e-mail do lead')
    expect(audits('proposal.approval_requested').sole).to have_attributes(subject: opportunity, correlation_id: quote_request.correlation_id)
  end

  it 'sends no 2nd e-mail on a second run (RF-02, RNF-02)' do
    run_service

    expect { run_service }.not_to change(Message, :count)
    expect(audits('proposal.approval_requested').count).to eq(1)
  end

  it 'warns about the missing lead e-mail in the body (RF-08)' do
    contact.update!(email: nil)

    run_service

    expect(email_conversation.messages.outgoing.sole.content).to include('falta e-mail do lead')
  end

  it 'fails with artifact_download_failed and sends nothing when the download fails (RF-01)' do
    stub_request(:get, artifact_url).to_return(status: 500)

    expect { run_service }.not_to change(Message, :count)

    expect(version).to have_attributes(status: 'failed', failure_reason: 'artifact_download_failed', approval_requested_at: nil)
    expect(audits('proposal.delivery_failed').sole).to have_attributes(correlation_id: quote_request.correlation_id)
    expect(audits('proposal.approval_requested').count).to eq(0)
  end

  context 'with the artifact checksum from Make (RF-25)' do
    let(:artifact_sha256) { Digest::SHA256.hexdigest(pdf_body) }

    it 'sends the approval request when the checksum matches' do
      expect { run_service }.to change(email_conversation.messages.outgoing, :count).by(1)
    end

    it 'fails with artifact_checksum_mismatch and sends nothing when it differs' do
      version.update!(artifact_sha256: 'f' * 64)

      expect { run_service }.not_to change(Message, :count)

      expect(version).to have_attributes(status: 'failed', failure_reason: 'artifact_checksum_mismatch')
      expect(version.document).not_to be_attached
      expect(audits('proposal.delivery_failed').count).to eq(1)
    end
  end

  it 'downloads again and requests the approval on an explicit redownload of a failed download (RF-15 c)' do
    stub_request(:get, artifact_url).to_return(status: 500).then
                                    .to_return(status: 200, body: pdf_body, headers: { 'Content-Type' => 'application/pdf' })
    run_service

    expect { run_service(redownload: true) }.to change(email_conversation.messages.outgoing, :count).by(1)
    expect(version).to have_attributes(status: 'awaiting_approval', failure_reason: nil)
  end

  it 'refuses to run inside an open transaction (RNF-01)' do
    expect do
      ActiveRecord::Base.transaction { described_class.call(proposal_version: version) }
    end.to raise_error(CustomExceptions::ScanSolo::DeliveryInsideTransaction)
    expect(Message.count).to eq(0)
  end
end
