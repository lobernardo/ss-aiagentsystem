# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Handoff::TakeoverService do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def call(**)
    described_class.call(conversation: conversation, reason: 'cliente pediu humano', actor: agent, **)
  end

  it 'moves the conversation to human_active with the handoff note and an explicit takeover audit by default' do
    call

    expect(ScanSolo::ConversationExtension.resolve_for(conversation)).to be_human_active
    expect(conversation.messages.where(private: true).count).to eq(1)
    event = ScanSolo::AuditEvent.find_by!(event_type: 'handoff.takeover')
    expect(event.actor).to eq(agent)
    expect(event.payload).to include('trigger' => 'explicit', 'reason' => 'cliente pediu humano')
  end

  it 'records the implicit human_reply trigger (RF-18)' do
    call(trigger: 'human_reply')

    expect(ScanSolo::AuditEvent.find_by!(event_type: 'handoff.takeover').payload['trigger']).to eq('human_reply')
  end

  it 'pauses the active enrollments and keeps their attempts scheduled (RF-19)' do
    opportunity = ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
    definition = ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2, 24])
    enrollment = ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: definition)

    call

    expect(enrollment.reload).to be_paused
    expect(enrollment.attempts.pluck(:result).uniq).to eq(['scheduled'])
  end

  it 'is a no-op while already human_active' do
    call

    expect { call(trigger: 'human_reply') }.not_to change(ScanSolo::AuditEvent, :count)
  end
end
