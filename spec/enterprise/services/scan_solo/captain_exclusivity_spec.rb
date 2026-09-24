require 'rails_helper'

RSpec.describe ScanSolo::Eligibility do # rubocop:disable RSpec/SpecFilePathFormat -- Phase contract names this exclusivity spec.
  it 'rejects an allowlisted inbox when the Enterprise bot check reports an active assistant' do
    account = create(:account, scansolo_enabled: true)
    inbox = create(:inbox, account: account)
    assistant = create(:captain_assistant, account: account)
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant)
    allow(account).to receive(:usage_limits).and_return(captain: { responses: { current_available: 10 } })
    inbox.account = account
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(enabled: true, allowed_inbox_ids: [inbox.id])
    ScanSolo::AiAgent::PublishService.new(account: account).call

    expect(inbox).to be_active_bot
    result = described_class.for_inbox(account: account, inbox: inbox)
    expect(result).not_to be_eligible
    expect(result.reason).to eq('inbox_has_active_bot')
  end
end
