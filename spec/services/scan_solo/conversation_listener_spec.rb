# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::ConversationListener do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
  end

  let(:listener) { described_class.instance }

  def inbound_message
    create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact)
  end

  it 'records the customer interaction timestamp and applies the RF-14 rule' do
    message = inbound_message
    event = Events::Base.new('message_created', Time.zone.now, { message: message })

    listener.message_created(event)

    opportunity.reload
    expect(opportunity.last_customer_interaction_at).to be_within(1.second).of(message.created_at)
    expect(opportunity.stage).to eq('em_contato')
  end

  it 'is registered on the AsyncDispatcher listener seam' do
    expect(AsyncDispatcher.new.listeners).to include(described_class.instance)
  end

  describe 'RF-35/RF-96: enqueues the guarded AI turn job for the persisted message' do
    it 'enqueues ScanSolo::AiTurnJob with the message id' do
      message = inbound_message
      event = Events::Base.new('message_created', Time.zone.now, { message: message })

      expect { listener.message_created(event) }
        .to have_enqueued_job(ScanSolo::AiTurnJob).with(message.id)
    end
  end

  describe 'RF-95: zero footprint on an account without ScanSolo enabled' do
    let(:disabled_account) { create(:account, scansolo_enabled: false) }
    let(:disabled_contact) { create(:contact, account: disabled_account) }
    let(:disabled_conversation) { create(:conversation, account: disabled_account, contact: disabled_contact) }

    it 'does not enqueue an AI turn job' do
      message = create(:message, account: disabled_account, conversation: disabled_conversation,
                                 message_type: :incoming, sender: disabled_contact)
      event = Events::Base.new('message_created', Time.zone.now, { message: message })

      expect { listener.message_created(event) }
        .not_to have_enqueued_job(ScanSolo::AiTurnJob)
    end
  end
end
