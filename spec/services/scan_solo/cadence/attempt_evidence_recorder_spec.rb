# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Cadence::AttemptEvidenceRecorder do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
  end
  let(:cadence_definition) { ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2, 24]) }
  let(:enrollment) { ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: cadence_definition) }
  let(:first_attempt) { enrollment.attempts.order(:step).first }
  let(:second_attempt) { enrollment.attempts.order(:step).second }

  describe '.record_sent!' do
    it 'records exactly one evidence result for the attempt and advances the enrollment (RF-62, RF-63)' do
      described_class.record_sent!(first_attempt)

      first_attempt.reload
      expect(first_attempt).to be_sent
      expect(first_attempt.sent_at).to be_present

      enrollment.reload
      expect(enrollment.current_step).to eq(1)
      expect(enrollment.next_attempt_at).to eq(second_attempt.scheduled_at)
    end

    it 'never updates the record again once it has a terminal result' do
      described_class.record_sent!(first_attempt)

      expect { described_class.record_sent!(first_attempt) }.to raise_error(described_class::AlreadyRecordedError)
    end
  end

  describe '.record_failed!' do
    it 'records a terminal failed result without touching sent_at' do
      described_class.record_failed!(first_attempt)

      first_attempt.reload
      expect(first_attempt).to be_failed
      expect(first_attempt.sent_at).to be_nil
    end
  end

  describe '.record_skipped!' do
    it 'records a terminal skipped result' do
      described_class.record_skipped!(first_attempt)

      expect(first_attempt.reload).to be_skipped
    end
  end

  describe 'completing every attempt' do
    it 'marks the enrollment completed with no next attempt once the last attempt resolves' do
      described_class.record_sent!(first_attempt)
      described_class.record_sent!(second_attempt)

      enrollment.reload
      expect(enrollment).to be_completed
      expect(enrollment.next_attempt_at).to be_nil
    end
  end

  describe ScanSolo::CadenceEnrollmentSerializer do
    it 'serializes next_attempt_at matching the persisted enrollment value' do
      ScanSolo::Cadence::AttemptEvidenceRecorder.record_sent!(first_attempt)

      json = ScanSolo::CadenceEnrollmentSerializer.new(enrollment.reload).as_json

      expect(json[:next_attempt_at]).to eq(enrollment.next_attempt_at)
      expect(json[:current_step]).to eq(enrollment.current_step)
      expect(json[:status]).to eq(enrollment.status)
    end
  end
end
