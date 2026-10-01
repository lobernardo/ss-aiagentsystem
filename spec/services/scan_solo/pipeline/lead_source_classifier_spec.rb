# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Pipeline::LeadSourceClassifier do
  subject(:lead_source) { described_class.call(conversation: conversation) }

  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def create_message(message_type, created_at, **attributes)
    create(:message, account: account, conversation: conversation, message_type: message_type, created_at: created_at, **attributes)
  end

  it 'is website when the first message is the customer incoming (RF-02)' do
    create_message(:incoming, 2.hours.ago, sender: contact)
    create_message(:outgoing, 1.hour.ago, sender: agent)

    expect(lead_source).to eq('website')
  end

  it 'is manual when the first message is a native outgoing sent by a team member' do
    create_message(:outgoing, 2.hours.ago, sender: agent)
    create_message(:incoming, 1.hour.ago, sender: contact)

    expect(lead_source).to eq('manual')
  end

  it 'is nil when the first message is an outgoing sent by an agent bot' do
    create_message(:outgoing, 2.hours.ago, sender: create(:agent_bot, account: account))
    create_message(:incoming, 1.hour.ago, sender: contact)

    expect(lead_source).to be_nil
  end

  it 'is nil when the first message is an outgoing without sender (campaign/automation)' do
    create_message(:outgoing, 2.hours.ago, additional_attributes: { 'campaign_id' => 1 })
      .update_columns(sender_type: nil, sender_id: nil) # rubocop:disable Rails/SkipsModelValidations
    create_message(:incoming, 1.hour.ago, sender: contact)

    expect(lead_source).to be_nil
  end

  it 'ignores private notes and activity messages before the first incoming' do
    create_message(:outgoing, 3.hours.ago, sender: agent, private: true)
    create_message(:activity, 150.minutes.ago, sender: nil)
    create_message(:incoming, 2.hours.ago, sender: contact)

    expect(lead_source).to eq('website')
  end

  it 'is nil for a conversation without messages' do
    expect(lead_source).to be_nil
  end
end
