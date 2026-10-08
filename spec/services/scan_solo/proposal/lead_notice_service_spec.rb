# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Proposal::LeadNoticeService do
  before { stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook') }

  let(:account) { create(:account, scansolo_enabled: true) }
  let(:channel) { create(:channel_whatsapp, account: account, sync_templates: false, message_templates: templates) }
  let(:templates) do
    [{ 'name' => 'scansolo_proposta_aviso_email', 'language' => 'pt_BR', 'status' => 'APPROVED',
       'components' => [{ 'type' => 'BODY', 'text' => 'Olá, enviamos a proposta para o seu e-mail.' }] }]
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, email: 'ana@solar.example') }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511955554444') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :proposta_enviada)
  end
  let(:quote_request) do
    ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid, status: :replied,
                                   commercial: { 'total_value' => '12500.00' })
  end
  let(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
  let(:version) do
    proposal.versions.create!(status: :sent, quote_request: quote_request, value: 12_500, currency: 'BRL', approved_at: Time.current).tap do |created|
      created.document.attach(io: StringIO.new('%PDF-1.4 proposta'), filename: "#{created.proposal_number}.pdf", content_type: 'application/pdf')
    end
  end
  let(:notices) { conversation.messages.where("additional_attributes ->> 'scansolo_origin' = 'proposal_notice'") }
  let(:notice_failures) { ScanSolo::AuditEvent.where(event_type: 'proposal.lead_notice_failed') }

  def call(target = version)
    described_class.call(proposal_version: target)
  end

  it 'sends one WhatsApp notice without the document for a sent version (RF-11, CT-07)' do
    call

    notice = notices.sole
    template_params = notice.additional_attributes['template_params']
    expect(template_params).to include('name' => 'scansolo_proposta_aviso_email')
    expect(template_params['processed_params'].to_h).not_to have_key('header')
    expect(template_params.to_json).not_to include('media_url')
    expect(notice.content).not_to include('http')
    expect(version.reload).to have_attributes(status: 'sent', notice_message_id: notice.id, notice_failure_reason: nil)
  end

  it 'keeps one notice on a 2nd call (RF-12, RNF-02)' do
    call
    call(ScanSolo::ProposalVersion.find(version.id))

    expect(notices.count).to eq(1)
  end

  it 'sends a new notice only when the previous one failed (RF-12, RF-15 a)' do
    call
    notices.sole.update!(status: :failed)

    call(ScanSolo::ProposalVersion.find(version.id))

    expect(notices.count).to eq(2)
    expect(version.reload.notice_message).to eq(notices.order(:id).last)
  end

  it 'audits a blocked template and keeps the version sent (RF-14)' do
    channel.update!(message_templates: [])

    call

    expect(notices.count).to eq(0)
    expect(version.reload).to have_attributes(status: 'sent', notice_failure_reason: 'template_missing', notice_message_id: nil)
    expect(notice_failures.sole).to have_attributes(subject: opportunity, correlation_id: quote_request.correlation_id)
    expect(notice_failures.sole.payload).to include('proposal_version_id' => version.id, 'reason' => 'template_missing')
  end

  it 'sends no notice before the version is sent (RF-11, RF-13)' do
    version.update!(status: :approved)

    call

    expect(notices.count).to eq(0)
    expect(notice_failures).to be_none
  end

  it 'creates no Make request and no e-mail (RF-11)' do
    expect { call }.not_to change(ScanSolo::MakeRequest, :count)
    expect(Message.where.not(conversation: conversation).count).to eq(0)
  end
end
