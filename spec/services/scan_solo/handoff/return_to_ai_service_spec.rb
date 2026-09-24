# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Handoff::ReturnToAiService do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
  end
  let!(:cadence_definition) { ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2, 24]) }

  it 'returns to ai_active, audits once and resumes the paused cadence shifted by the takeover duration (RF-20, RF-29)' do
    enrollment = ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: cadence_definition)
    first_scheduled_at = enrollment.attempts.order(:step).first.scheduled_at
    ScanSolo::Handoff::TakeoverService.call(conversation: conversation, reason: 'humano', actor: agent)
    expect(enrollment.reload).to be_paused

    travel_to(30.hours.from_now) { described_class.call(conversation: conversation, actor: agent) }

    expect(ScanSolo::ConversationExtension.resolve_for(conversation)).to be_ai_active
    expect(ScanSolo::AuditEvent.where(event_type: 'handoff.return_to_ai').count).to eq(1)
    expect(enrollment.reload).to be_active
    expect(enrollment.attempts.order(:step).first.scheduled_at).to be_within(1.second).of(first_scheduled_at + 30.hours)
  end

  it 'enrolls the current stage when no enrollment is open (RF-29)' do
    opportunity
    ScanSolo::ConversationExtension.resolve_for(conversation).update!(ai_control_state: :human_active)

    described_class.call(conversation: conversation, actor: agent)

    expect(opportunity.cadence_enrollments.active.count).to eq(1)
  end

  it 'is a no-op while already ai_active' do
    expect { described_class.call(conversation: conversation, actor: agent) }.not_to change(ScanSolo::AuditEvent, :count)
  end
end
