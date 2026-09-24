# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Cadence::ResumeOnReturnService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_contato)
  end
  let!(:cadence_definition) { ScanSolo::CadenceDefinition.create!(stage: 'em_contato', version: 1, offsets: [24, 48]) }

  it 'resumes the paused enrollment shifting the remaining attempts by the paused duration (RF-29)' do
    enrollment = ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: cadence_definition)
    original = enrollment.attempts.order(:step).pluck(:scheduled_at)
    ScanSolo::Cadence::StopRecalculatePolicy.handle_takeover(opportunity: opportunity)

    travel_to(30.hours.from_now) { described_class.call(opportunity: opportunity) }

    enrollment.reload
    expect(enrollment).to be_active
    shifted = enrollment.attempts.order(:step).pluck(:scheduled_at)
    expect(shifted.zip(original).map { |after, before| (after - before).round }).to all(be_within(1).of(30.hours.to_i))
    expect(enrollment.next_attempt_at).to eq(shifted.first)
  end

  it 'creates a new enrollment when the current stage has no open one (RF-29, RF-30)' do
    expect { described_class.call(opportunity: opportunity) }.to change { opportunity.cadence_enrollments.active.count }.from(0).to(1)
  end

  it 'creates nothing for an opted-out contact (RF-31)' do
    ScanSolo::ContactExtension.resolve_for(contact).update!(opted_out: true)

    expect { described_class.call(opportunity: opportunity) }.not_to change(ScanSolo::CadenceEnrollment, :count)
  end

  it 'leaves an already active enrollment untouched' do
    enrollment = ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: cadence_definition)

    expect { described_class.call(opportunity: opportunity) }.not_to(change { enrollment.reload.attributes })
  end
end
