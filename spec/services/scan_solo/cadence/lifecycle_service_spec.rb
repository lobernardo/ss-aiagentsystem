# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Cadence::LifecycleService do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
  end
  let(:cadence_definition) { ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2, 24, 48]) }

  before do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente', enabled: true, allowed_inbox_ids: [conversation.inbox_id])
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  describe '.enroll! authorization (RF-68)' do
    it 'rejects an unauthorized manual-enrollment request' do
      expect do
        described_class.enroll!(opportunity: opportunity, cadence_definition: cadence_definition, authorized: false)
      end.to raise_error(described_class::UnauthorizedError)

      expect(ScanSolo::CadenceEnrollment.where(opportunity: opportunity)).to be_none
    end

    it 'creates the enrollment when explicitly authorized' do
      enrollment = described_class.enroll!(opportunity: opportunity, cadence_definition: cadence_definition, authorized: true)

      expect(enrollment).to be_persisted
      expect(enrollment).to be_active
    end
  end

  describe '.enroll! with test_mode (RF-68)' do
    it 'advances through all configured attempts without real wall-clock waiting' do
      enrollment = described_class.enroll!(
        opportunity: opportunity, cadence_definition: cadence_definition, authorized: true, test_mode: true
      )

      expect(enrollment.attempts.pluck(:result).uniq).to eq(['dispatched'])
      expect(enrollment).to be_completed
    end
  end

  describe 'pause/resume/cancel (RF-64)' do
    let(:enrollment) do
      described_class.enroll!(opportunity: opportunity, cadence_definition: cadence_definition, authorized: true)
    end

    it 'pausing prevents the next attempt from firing' do
      next_attempt = enrollment.attempts.order(:scheduled_at).first

      described_class.pause!(enrollment)
      enrollment.reload

      expect(enrollment).to be_paused
      expect(enrollment.next_attempt_at).to be_nil

      travel_to(next_attempt.scheduled_at + 1.hour) do
        ScanSolo::CadenceDueAttemptJob.process_attempt!(next_attempt.reload)
      end

      expect(next_attempt.reload).to be_scheduled
    end

    it 'resuming re-arms at the correct offset, shifted forward by the pause duration' do
      first_attempt = enrollment.attempts.order(:scheduled_at).first
      original_scheduled_at = first_attempt.scheduled_at

      travel_to(Time.current) do
        described_class.pause!(enrollment)
      end

      resumed_at = enrollment.reload.paused_at + 3.hours

      travel_to(resumed_at) do
        described_class.resume!(enrollment)
      end

      enrollment.reload
      expect(enrollment).to be_active
      expect(first_attempt.reload.scheduled_at).to eq(original_scheduled_at + 3.hours)
    end

    it 'cancelling stops all remaining attempts permanently' do
      described_class.cancel!(enrollment)
      enrollment.reload

      expect(enrollment).to be_cancelled
      expect(enrollment.next_attempt_at).to be_nil
      expect(enrollment.attempts.pluck(:result).uniq).to eq(['cancelled'])
    end
  end
end
