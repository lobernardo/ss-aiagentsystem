# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::OptOut::MarkService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:other_conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
  end
  let(:other_opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: other_conversation, stage: :em_contato)
  end
  let(:novo_lead) { ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2, 24]) }
  let(:em_contato) { ScanSolo::CadenceDefinition.create!(stage: 'em_contato', version: 1, offsets: [24, 48]) }

  it 'persists the marker and cancels every active or paused enrollment of the contact (RF-16, RF-31)' do
    ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: novo_lead)
    paused = ScanSolo::Cadence::EnrollmentService.call(opportunity: other_opportunity, cadence_definition: em_contato)
    ScanSolo::Cadence::LifecycleService.pause!(paused)

    extension = described_class.call(contact: contact, source: 'keyword')

    expect(extension).to have_attributes(opted_out: true, opted_out_source: 'keyword')
    expect(extension.opted_out_at).to be_present
    expect(ScanSolo::CadenceEnrollment.where(status: %i[active paused]).count).to eq(0)
    expect(ScanSolo::CadenceAttempt.scheduled.count).to eq(0)
  end

  it 'keeps the original opt-out source and time when marked again' do
    first = described_class.call(contact: contact, source: 'keyword')

    second = travel_to(1.hour.from_now) { described_class.call(contact: contact, source: 'model_action') }

    expect(second.opted_out_source).to eq('keyword')
    expect(second.opted_out_at).to eq(first.opted_out_at)
  end
end
