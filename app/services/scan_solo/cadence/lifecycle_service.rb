# RF-64/RF-68: the sole path for pausing, resuming, cancelling and manually
# enrolling a cadence. Manual enrollment requires an explicit `authorized:
# true` (RF-68) -- the controller (T56) only ever passes that after its own
# Pundit check, so this is a defense-in-depth guard against any other
# caller skipping authorization, not the only gate.
#
# `pause_all_for_opportunity!`/`cancel_all_for_opportunity!` are the shared
# "stop pending cadence work for this opportunity" primitives reused by
# ScanSolo::Cadence::ReplyCompletenessDetector (T52) and
# ScanSolo::Cadence::StopRecalculatePolicy (T53), so there is exactly one
# implementation of "stop everything" rather than one per caller.
class ScanSolo::Cadence::LifecycleService
  class UnauthorizedError < StandardError; end

  def self.enroll!(opportunity:, cadence_definition:, actor: nil, authorized: false, test_mode: false)
    raise UnauthorizedError, 'manual cadence enrollment requires explicit authorization' unless authorized

    enrollment = ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: cadence_definition)
    accelerate!(enrollment) if test_mode
    enrollment.reload
  end

  def self.pause!(enrollment)
    return enrollment unless enrollment.active?

    enrollment.update!(status: :paused, paused_at: Time.current, next_attempt_at: nil)
    enrollment
  end

  def self.resume!(enrollment)
    return enrollment unless enrollment.paused?

    pause_duration = Time.current - enrollment.paused_at

    ActiveRecord::Base.transaction do
      enrollment.attempts.scheduled.find_each do |attempt|
        attempt.update!(scheduled_at: attempt.scheduled_at + pause_duration)
      end

      enrollment.update!(
        status: :active,
        paused_at: nil,
        next_attempt_at: enrollment.attempts.scheduled.order(:scheduled_at).first&.scheduled_at
      )
    end

    enrollment
  end

  def self.cancel!(enrollment)
    return enrollment if enrollment.cancelled?

    ActiveRecord::Base.transaction do
      enrollment.attempts.scheduled.find_each { |attempt| ScanSolo::Cadence::AttemptEvidenceRecorder.record_cancelled!(attempt) }
      enrollment.update!(status: :cancelled, next_attempt_at: nil)
    end

    enrollment
  end

  def self.pause_all_for_opportunity!(opportunity)
    opportunity.cadence_enrollments.active.find_each { |enrollment| pause!(enrollment) }
  end

  def self.cancel_all_for_opportunity!(opportunity)
    opportunity.cadence_enrollments.where(status: %i[active paused]).find_each { |enrollment| cancel!(enrollment) }
  end

  def self.accelerate!(enrollment)
    enrollment.attempts.scheduled.order(:scheduled_at).each do |attempt|
      ScanSolo::CadenceDueAttemptJob.process_attempt!(attempt, enforce_window: false)
    end
  end
end
