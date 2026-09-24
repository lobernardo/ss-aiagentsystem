# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Actions::HandoffAction do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
  end
  let(:definition) { ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2, 24]) }

  def call
    described_class.call(params: { conversation_id: conversation.id, reason: 'cliente pediu humano' })
  end

  it 'moves the conversation to awaiting_human with the nine-line handoff note (RF-15)' do
    result = call

    expect(result).to eq(status: 'awaiting_human', conversation_id: conversation.id, reason: 'cliente pediu humano')
    expect(ScanSolo::ConversationExtension.resolve_for(conversation)).to be_awaiting_human
    expect(conversation.messages.where(private: true).sole.content).to include('Motivo da transferência: cliente pediu humano')
  end

  it 'pauses the active enrollments with their attempts still scheduled' do
    enrollment = ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: definition)

    call

    expect(enrollment.reload).to be_paused
    expect(enrollment.attempts.pluck(:result).uniq).to eq(['scheduled'])
  end

  it 'works for a conversation without an opportunity' do
    expect { call }.not_to raise_error
  end
end
