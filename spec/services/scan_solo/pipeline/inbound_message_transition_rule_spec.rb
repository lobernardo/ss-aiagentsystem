# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Pipeline::InboundMessageTransitionRule do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
  end

  def inbound_message
    create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact)
  end

  it 'moves a Novo Lead opportunity to Em Contato on a real inbound message' do
    described_class.call(message: inbound_message)

    expect(opportunity.reload.stage).to eq('em_contato')
  end

  it 'does not re-trigger on a second inbound message' do
    described_class.call(message: inbound_message)
    expect(opportunity.reload.stage).to eq('em_contato')

    expect do
      described_class.call(message: inbound_message)
    end.not_to change(ScanSolo::PipelineStageEvent, :count)

    expect(opportunity.reload.stage).to eq('em_contato')
  end

  it 'ignores an outgoing message' do
    outgoing = create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: create(:user, account: account))

    described_class.call(message: outgoing)

    expect(opportunity.reload.stage).to eq('novo_lead')
  end

  it 'is a no-op when no opportunity exists for the conversation' do
    other_conversation = create(:conversation, account: account)
    message = create(:message, account: account, conversation: other_conversation, message_type: :incoming, sender: contact)

    expect { described_class.call(message: message) }.not_to raise_error
  end
end
