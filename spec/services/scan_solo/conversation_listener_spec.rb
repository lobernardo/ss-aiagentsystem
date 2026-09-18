# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::ConversationListener do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
  end

  let(:listener) { described_class.instance }

  it 'records the customer interaction timestamp and applies the RF-14 rule' do
    message = create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact)
    event = Events::Base.new('message_created', Time.zone.now, { message: message })

    listener.message_created(event)

    opportunity.reload
    expect(opportunity.last_customer_interaction_at).to be_within(1.second).of(message.created_at)
    expect(opportunity.stage).to eq('em_contato')
  end

  it 'is registered on the AsyncDispatcher listener seam' do
    expect(AsyncDispatcher.new.listeners).to include(described_class.instance)
  end
end
