# RF-62/RF-63/RF-27: the sole writer of a cadence attempt's result. Each
# attempt row already carries its own immutable evidence (cadence version,
# template reference, scheduled time -- all set once at enrollment); this
# class records the other half and refuses a second write once an attempt
# is terminal, then keeps the owning enrollment's `current_step`/
# `next_attempt_at` in sync in the same transaction.
#
# A send first records `dispatched` with the native message id; only
# ScanSolo::Messaging::DeliveryReconciler turns it into `sent` (provider
# accepted) or `failed` (with the native external error). A precheck block
# (`record_blocked!`) only notes the reason and check time -- the attempt
# stays `scheduled` and the enrollment is untouched (RF-26).
class ScanSolo::Cadence::AttemptEvidenceRecorder
  class AlreadyRecordedError < StandardError; end

  def self.record_blocked!(attempt, reason:)
    attempt.update!(last_block_reason: reason, last_checked_at: Time.current)
    attempt
  end

  def self.record_dispatched!(attempt, message:)
    new(attempt).record!(result: :dispatched, message: message, last_checked_at: Time.current)
  end

  def self.record_sent!(attempt)
    new(attempt).record!(result: :sent, sent_at: Time.current)
  end

  def self.record_failed!(attempt, external_error: nil)
    new(attempt).record!(result: :failed, external_error: external_error)
  end

  def self.record_cancelled!(attempt)
    new(attempt).record!(result: :cancelled)
  end

  def initialize(attempt)
    @attempt = attempt
  end

  def record!(result:, **evidence)
    raise AlreadyRecordedError, "cadence attempt #{attempt.id} already has a terminal result" if attempt.terminal?

    ActiveRecord::Base.transaction do
      attempt.update!(result: result, **evidence)
      advance_enrollment!
    end

    attempt
  end

  private

  attr_reader :attempt

  def advance_enrollment!
    enrollment = attempt.enrollment.lock!
    next_attempt = enrollment.attempts.scheduled.order(:scheduled_at).first
    max_terminal_step = enrollment.attempts.where.not(result: :scheduled).maximum(:step) || 0

    updates = { current_step: max_terminal_step }

    if enrollment.active?
      updates[:next_attempt_at] = next_attempt&.scheduled_at
      updates[:status] = :completed if next_attempt.blank?
    end

    enrollment.update!(updates)
  end
end
