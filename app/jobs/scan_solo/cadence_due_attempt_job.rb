# RF-58/RF-60/RF-61: registered in config/schedule.yml as a sidekiq-cron
# entry running every 5 minutes (RNF-08: a due in-window attempt that passes
# every check is dispatched within one cycle). Each due attempt is locked
# (`SELECT ... FOR UPDATE`) and re-read as `scheduled`, so a retried or
# duplicate run produces zero additional sends (RF-61).
#
# The job owns no eligibility logic: ScanSolo::Cadence::AttemptPrecheck
# decides send/cancel/defer (RF-26). A deferral keeps the attempt
# `scheduled` and never touches `current_step`; outside the sending window
# (RF-58) the attempt moves to the next in-window moment. A send creates the
# native message and records the attempt `dispatched` -- `sent` only comes
# from ScanSolo::Messaging::DeliveryReconciler once the provider accepts it
# (RF-27). A send that happens later than planned because of a deferral
# shifts the enrollment's remaining attempts by the same delay, and at most
# one attempt per enrollment is sent per run (RF-29).
class ScanSolo::CadenceDueAttemptJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    dispatched_enrollment_ids = Set.new

    ScanSolo::CadenceAttempt.scheduled.where('scheduled_at <= ?', Time.current).order(:scheduled_at).each do |attempt|
      next if dispatched_enrollment_ids.include?(attempt.enrollment_id)

      dispatched_enrollment_ids << attempt.enrollment_id if self.class.process_attempt!(attempt)
    end
  end

  # Returns true when the attempt was dispatched.
  def self.process_attempt!(attempt, enforce_window: true)
    ScanSolo::CadenceAttempt.transaction do
      locked_attempt = ScanSolo::CadenceAttempt.lock.find(attempt.id)
      next false unless locked_attempt.scheduled? && locked_attempt.enrollment.active?

      apply_precheck!(locked_attempt, ScanSolo::Cadence::AttemptPrecheck.call(attempt: locked_attempt), enforce_window)
    end
  end

  def self.apply_precheck!(attempt, precheck, enforce_window)
    case precheck.decision
    when :defer
      ScanSolo::Cadence::AttemptEvidenceRecorder.record_blocked!(attempt, reason: precheck.reason)
      false
    when :cancel
      ScanSolo::Cadence::AttemptEvidenceRecorder.record_blocked!(attempt, reason: precheck.reason)
      ScanSolo::Cadence::LifecycleService.cancel!(attempt.enrollment)
      false
    else
      send_in_window!(attempt, precheck.template, enforce_window)
    end
  end

  def self.send_in_window!(attempt, template, enforce_window)
    if enforce_window && !ScanSolo::Cadence::SendingWindow.in_window?
      attempt.update!(scheduled_at: ScanSolo::Cadence::SendingWindow.next_in_window)
      return false
    end

    send_attempt!(attempt, template)
  end

  def self.send_attempt!(attempt, template)
    enrollment = attempt.enrollment
    message = ScanSolo::Messaging::NativeTemplateSender.call(
      conversation: enrollment.opportunity.conversation, template_reference: template.name,
      template_params: template.sender_params, origin: 'cadence'
    ).message
    shift_remaining_attempts!(attempt) if attempt.last_block_reason.present?
    ScanSolo::Cadence::AttemptEvidenceRecorder.record_dispatched!(attempt, message: message)
    true
  rescue StandardError => e
    Rails.logger.error("ScanSolo::CadenceDueAttemptJob failed to send attempt #{attempt.id}: #{e.message}")
    ScanSolo::Cadence::AttemptEvidenceRecorder.record_failed!(attempt, external_error: e.message)
    false
  end

  def self.shift_remaining_attempts!(attempt)
    delay = Time.current - attempt.scheduled_at
    return unless delay.positive?

    attempt.enrollment.attempts.scheduled.where.not(id: attempt.id).find_each do |later_attempt|
      later_attempt.update!(scheduled_at: later_attempt.scheduled_at + delay)
    end
  end
  private_class_method :apply_precheck!, :send_in_window!, :send_attempt!, :shift_remaining_attempts!
end
