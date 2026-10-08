# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::ProposalApprovalRequestJob do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:customer_inbox) { create(:inbox, account: account) }
  let(:email_inbox) { create(:channel_email, account: account, email: 'atendimento.comercial@scansolo.com.br').inbox }
  let(:contact) { create(:contact, account: account, email: 'ana@solar.example') }
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
  let(:correlation_id) { SecureRandom.uuid }
  let(:version) do
    ScanSolo::Proposal.create!(opportunity: opportunity).versions.create!(quote_request: quote_request, generate_correlation_id: correlation_id)
  end
  let(:artifact_url) { 'https://make.example/proposals/7.pdf' }

  before do
    ScanSolo::AiAgentConfig.draft_for!(account).update!(name: 'Agente', enabled: true, allowed_inbox_ids: [customer_inbox.id],
                                                        quote_inbox_id: email_inbox.id)
    ScanSolo::AiAgent::PublishService.new(account: account).call
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('make.example').and_return(['93.184.216.34'])
    stub_request(:get, artifact_url).to_return(status: 200, body: '%PDF-1.4 proposta', headers: { 'Content-Type' => 'application/pdf' })
  end

  it 'runs on the medium queue' do
    expect(described_class.new.queue_name).to eq('medium')
  end

  it 'stores the PDF and posts one approval request after the generate callback commits, once (RF-01, RF-02)' do
    perform_enqueued_jobs(only: described_class) do
      ScanSolo::Proposal::CallbackHandler.apply_generate_result!(
        proposal_version: version, correlation_id: correlation_id, success: true, value: 12_500, currency: 'BRL', artifact_url: artifact_url
      )
    end

    expect(version.reload.document.blob.content_type).to eq('application/pdf')
    message = email_conversation.messages.outgoing.sole
    expect(message.content_attributes['to_emails']).to eq(['comercial@scansolo.com.br'])
    expect(message.attachments.sole.file.filename.to_s).to eq("#{version.proposal_number}.pdf")

    expect { described_class.perform_now(version.id) }.not_to change(Message, :count)
  end
end
