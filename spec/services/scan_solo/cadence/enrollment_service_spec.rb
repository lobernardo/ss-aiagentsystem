# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Cadence::EnrollmentService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
  end
  let(:cadence_definition) { ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2, 24, 48, 96]) }

  def call
    described_class.call(opportunity: opportunity, cadence_definition: cadence_definition)
  end

  it 'creates exactly one active enrollment with all attempts scheduled' do
    enrollment = call

    expect(enrollment).to be_persisted
    expect(enrollment).to be_active
    expect(enrollment.attempts.count).to eq(4)
    expect(enrollment.next_attempt_at).to eq(enrollment.attempts.order(:scheduled_at).first.scheduled_at)
  end

  it 'is idempotent: calling enrollment twice with identical inputs results in exactly one active enrollment record (RF-59)' do
    first = call

    expect { call }.not_to change(ScanSolo::CadenceEnrollment, :count)

    second = call
    expect(second.id).to eq(first.id)
    expect(ScanSolo::CadenceEnrollment.where(opportunity: opportunity, cadence_definition: cadence_definition).count).to eq(1)
  end

  it 'does not duplicate scheduled attempts on a repeat call' do
    call
    call

    expect(ScanSolo::CadenceEnrollment.find_by(opportunity: opportunity, cadence_definition: cadence_definition).attempts.count).to eq(4)
  end
end
