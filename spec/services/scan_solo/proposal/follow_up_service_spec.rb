# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Proposal::FollowUpService do
  before do
    stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
    ScanSolo::CadenceDefinition.create!(stage: 'proposta_enviada', version: 1, offsets: [24, 72, 168])
  end

  let(:account) { create(:account, scansolo_enabled: true) }
  let(:channel) { create(:channel_whatsapp, account: account, sync_templates: false, message_templates: templates) }
  let(:templates) do
    %w[scansolo_proposal_send scansolo_proposta_acompanhamento].map do |name|
      { 'name' => name, 'language' => 'pt_BR', 'status' => 'APPROVED', 'components' => [{ 'type' => 'BODY', 'text' => 'Olá' }] }
    end
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511955554444') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end
  let(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
  let(:proposal_message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     additional_attributes: { 'scansolo_origin' => 'proposal' })
  end
  let!(:version) do
    proposal.versions.create!(status: :generated, value: 1000, currency: 'BRL', artifact_url: 'https://x.test/a.pdf',
                              generate_callback_applied_at: Time.current, sent_message: proposal_message)
  end
  let(:follow_ups) { conversation.messages.where("additional_attributes ->> 'scansolo_origin' = 'proposal_follow_up'") }

  def message_updated
    ScanSolo::ConversationListener.instance.message_updated(
      Events::Base.new('message_updated', Time.zone.now, { message: proposal_message.reload })
    )
  end

  it 'sends one follow-up after the proposal is accepted, even on a repeated message_updated (RF-31)' do
    proposal_message.update!(source_id: 'wamid.proposal')

    message_updated
    message_updated

    follow_up = follow_ups.sole
    expect(follow_up.additional_attributes).to include('scansolo_origin' => 'proposal_follow_up')
    expect(follow_up.additional_attributes['template_params']).to include('name' => 'scansolo_proposta_acompanhamento')
    expect(version.reload).to have_attributes(status: 'sent', follow_up_message_id: follow_up.id)
  end

  it 'sends no follow-up for a failed version' do
    proposal_message.update!(status: :failed, external_error: 'rejected')

    message_updated
    described_class.call(proposal_version: version.reload)

    expect(version).to be_failed
    expect(follow_ups.count).to eq(0)
  end

  it 'audits a blocked follow-up template and sends nothing' do
    channel.update!(message_templates: templates.first(1))
    version.update!(status: :sent)

    described_class.call(proposal_version: version)

    expect(follow_ups.count).to eq(0)
    expect(ScanSolo::AuditEvent.where(event_type: 'proposal.follow_up_blocked').sole.payload).to include('reason' => 'template_missing')
  end
end
