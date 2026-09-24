# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Actions::CadenceSignalAction do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
  end
  let(:cadence_definition) { ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2, 24]) }
  let!(:enrollment) { ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: cadence_definition) }

  def call(signal)
    described_class.call(params: { opportunity_id: opportunity.id, signal: signal })
  end

  it 'opt_out marks the contact through MarkService and leaves 0 active/paused enrollments (RF-16 (a))' do
    call('opt_out')

    expect(ScanSolo::ContactExtension.opted_out?(contact)).to be true
    expect(ScanSolo::ContactExtension.find_by(contact: contact).opted_out_source).to eq('model_action')
    expect(enrollment.reload).to be_cancelled
  end

  it 'manual_pause pauses the enrollment without opting the contact out' do
    call('manual_pause')

    expect(enrollment.reload).to be_paused
    expect(ScanSolo::ContactExtension.opted_out?(contact)).to be false
  end

  it 'records other signals without touching cadence state' do
    expect(call('partial_reply')).to include(status: 'signal_emitted', signal: 'partial_reply')
    expect(enrollment.reload).to be_active
  end
end
