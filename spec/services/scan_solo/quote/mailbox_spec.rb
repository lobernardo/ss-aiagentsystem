# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Quote::Mailbox do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:email_inbox) { create(:channel_email, account: account).inbox }
  let(:whatsapp_inbox) { create(:inbox, account: account) }
  let(:draft) { ScanSolo::AiAgentConfig.draft_for!(account) }

  def publish!(**attributes)
    draft.update!({ name: 'Agente', enabled: true, allowed_inbox_ids: [whatsapp_inbox.id] }.merge(attributes))
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  def expect_misconfigured(reason)
    expect { described_class.resolve!(account) }.to raise_error(CustomExceptions::ScanSolo::QuoteInboxMisconfigured) { |error|
      expect(error.reason).to eq(reason)
    }
  end

  it 'returns the published inbox and recipient' do
    publish!(quote_inbox_id: email_inbox.id)

    expect(described_class.resolve!(account)).to have_attributes(inbox: email_inbox, recipient: 'comercial@scansolo.com.br')
  end

  it 'keeps the published recipient while a new one is only in the draft (RF-54)' do
    publish!(quote_inbox_id: email_inbox.id, quote_recipient_email: 'luciano@scansolo.com.br')
    draft.update!(quote_recipient_email: 'outro@scansolo.com.br')

    expect(described_class.resolve!(account).recipient).to eq('luciano@scansolo.com.br')
  end

  it 'raises quote_inbox_missing without a published quote inbox (RF-14)' do
    publish!
    expect_misconfigured('quote_inbox_missing')
  end

  it 'raises quote_inbox_missing when the configured inbox no longer exists (RF-14)' do
    publish!(quote_inbox_id: 0)
    expect_misconfigured('quote_inbox_missing')
  end

  it 'raises quote_inbox_missing without any published config (RF-14)' do
    expect_misconfigured('quote_inbox_missing')
  end

  it 'raises quote_inbox_not_email for a non e-mail inbox (RF-14)' do
    publish!(quote_inbox_id: whatsapp_inbox.id)
    expect_misconfigured('quote_inbox_not_email')
  end

  it 'raises quote_inbox_allowlisted for an inbox in the published allowlist (RF-14, RF-16)' do
    publish!(quote_inbox_id: email_inbox.id, allowed_inbox_ids: [whatsapp_inbox.id, email_inbox.id])
    expect_misconfigured('quote_inbox_allowlisted')
  end
end
