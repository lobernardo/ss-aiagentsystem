require 'rails_helper'

RSpec.describe ScanSolo::Eligibility do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:draft) { ScanSolo::AiAgentConfig.draft_for!(account) }

  before do
    draft.update!(enabled: true, allowed_inbox_ids: [inbox.id])
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  it 'accepts an enabled published config with an allowlisted inbox and no bot' do
    result = described_class.for_inbox(account: account, inbox: inbox)
    expect(result).to be_eligible
    expect(result.reason).to be_nil
  end

  it 'rejects the disabled account before reading a config' do
    account.update!(scansolo_enabled: false)
    expect(ScanSolo::AiAgentConfig).not_to receive(:published_for)
    result = described_class.for_inbox(account: account, inbox: inbox)
    expect(result).not_to be_eligible
    expect(result.reason).to eq('scansolo_disabled')
  end

  it 'fails closed when no published config exists' do
    draft.update!(published_version: nil)
    expect(described_class.for_inbox(account: account, inbox: inbox).reason).to eq('config_unavailable')
  end

  it 'fails closed for a disabled published config' do
    draft.update!(enabled: false)
    ScanSolo::AiAgent::PublishService.new(account: account).call
    expect(described_class.for_inbox(account: account, inbox: inbox).reason).to eq('config_unavailable')
  end

  it 'uses the published allowlist instead of draft edits, and rejects an empty published list' do
    draft.update!(allowed_inbox_ids: [])
    expect(described_class.for_inbox(account: account, inbox: inbox)).to be_eligible
    ScanSolo::AiAgent::PublishService.new(account: account).call
    expect(described_class.for_inbox(account: account, inbox: inbox).reason).to eq('inbox_not_allowlisted')
  end

  it 'rejects an active native bot' do
    create(:agent_bot_inbox, inbox: inbox, status: :active)
    expect(described_class.for_inbox(account: account, inbox: inbox).reason).to eq('inbox_has_active_bot')
  end

  it 'classifies messages through the same inbox gate' do
    conversation = create(:conversation, account: account, inbox: inbox)
    message = create(:message, account: account, inbox: inbox, conversation: conversation)
    expect(described_class.for_message(message)).to be_eligible
  end
end
