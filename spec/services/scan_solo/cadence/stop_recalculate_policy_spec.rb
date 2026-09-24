# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Cadence::StopRecalculatePolicy do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
  end
  let(:cadence_definition) { ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2, 24]) }
  let!(:enrollment) do
    ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: cadence_definition)
  end

  describe 'RF-66: each of the six triggers stops/recalculates the pending schedule' do
    %w[stage_changed won lost opt_out replacement].each do |trigger|
      it "cancels every pending attempt for the '#{trigger}' trigger" do
        described_class.call(opportunity: opportunity, trigger: trigger)

        expect(enrollment.reload).to be_cancelled
        expect(enrollment.attempts.pluck(:result).uniq).to eq(['cancelled'])
      end
    end

    %w[manual_pause handoff].each do |trigger|
      it "pauses (reversibly) rather than cancels for the '#{trigger}' trigger" do
        described_class.call(opportunity: opportunity, trigger: trigger)

        expect(enrollment.reload).to be_paused
        expect(enrollment.attempts.pluck(:result).uniq).to eq(['scheduled'])
      end
    end

    it 'raises for an unknown trigger' do
      expect { described_class.call(opportunity: opportunity, trigger: 'made_up') }.to raise_error(ArgumentError)
    end
  end

  describe 'integration: stage change through StageTransitionService (T12)' do
    it 'stops pending cadence work when the opportunity transitions to ganho' do
      ScanSolo::Pipeline::StageTransitionService.new(opportunity: opportunity, target_stage: :ganho).call

      expect(enrollment.reload).to be_cancelled
    end

    it 'stops pending cadence work for any other stage change' do
      ScanSolo::Pipeline::StageTransitionService.new(opportunity: opportunity, target_stage: :em_contato).call

      expect(enrollment.reload).to be_cancelled
    end
  end

  describe 'integration: human takeover (RF-19, superseding the prior RF-56 cancel)' do
    let(:user) { create(:user, account: account) }

    it 'pauses the enrollment, keeps unsent attempts scheduled and leaves an already-sent step untouched' do
      sent_attempt = enrollment.attempts.order(:scheduled_at).first
      ScanSolo::Cadence::AttemptEvidenceRecorder.record_sent!(sent_attempt)
      pending_attempt = enrollment.attempts.order(:scheduled_at).second

      ScanSolo::Handoff::TakeoverService.call(conversation: conversation, reason: 'cliente pediu humano', actor: user)

      expect(enrollment.reload).to be_paused
      expect(sent_attempt.reload).to be_sent
      expect(pending_attempt.reload).to be_scheduled
    end
  end
end
