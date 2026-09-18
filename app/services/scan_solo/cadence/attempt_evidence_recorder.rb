# RF-62/RF-63: the sole writer of a cadence attempt's terminal result. Each
# attempt row already carries its own immutable evidence (cadence version,
# template reference, scheduled time -- all set once at enrollment by T48);
# this class records the other half (actual send time, result) exactly
# once and refuses a second write once an attempt is terminal, then keeps
# the owning enrollment's `current_step`/`next_attempt_at` (RF-63) in sync
# in the same transaction.
class ScanSolo::Cadence::AttemptEvidenceRecorder
  class AlreadyRecordedError < StandardError; end

  def self.record_sent!(attempt, message: nil)
    new(attempt).record!(result: :sent, sent_at: Time.current)
  end

  def self.record_skipped!(attempt)
    new(attempt).record!(result: :skipped, sent_at: nil)
  end

  def self.record_failed!(attempt)
    new(attempt).record!(result: :failed, sent_at: nil)
  end

  def self.record_cancelled!(attempt)
    new(attempt).record!(result: :cancelled, sent_at: nil)
  end

  def initialize(attempt)
    @attempt = attempt
  end

  def record!(result:, sent_at: nil)
    raise AlreadyRecordedError, "cadence attempt #{attempt.id} already has a terminal result" if attempt.terminal?

    ActiveRecord::Base.transaction do
      attempt.update!(result: result, sent_at: sent_at)
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
