# RF-58/RF-60/RF-61: registered in config/schedule.yml as a sidekiq-cron
# entry running every 5 minutes (not an external scheduler). Finds every
# scheduled attempt whose scheduled_at is due and processes it: outside the
# sending window (RF-58) it is deferred to the next in-window moment
# instead of sent; inside the window it is sent through
# ScanSolo::Messaging::NativeTemplateSender (T47) and its result recorded
# through ScanSolo::Cadence::AttemptEvidenceRecorder (T50).
#
# `process_attempt!` takes a row lock (`SELECT ... FOR UPDATE`) before
# checking the attempt is still `scheduled`, so a retried/duplicate job run
# racing the first one produces zero additional sends (RF-61) -- the second
# runner sees a non-scheduled row under the lock and no-ops.
class ScanSolo::CadenceDueAttemptJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    ScanSolo::CadenceAttempt.scheduled
                             .where('scheduled_at <= ?', Time.current)
                             .find_each { |attempt| self.class.process_attempt!(attempt) }
  end

  def self.process_attempt!(attempt, enforce_window: true)
    ScanSolo::CadenceAttempt.transaction do
      locked_attempt = ScanSolo::CadenceAttempt.lock.find(attempt.id)
      next unless locked_attempt.scheduled?

      enrollment = locked_attempt.enrollment
      next unless enrollment.active?

      if enforce_window && !ScanSolo::Cadence::SendingWindow.in_window?
        locked_attempt.update!(scheduled_at: ScanSolo::Cadence::SendingWindow.next_in_window)
        next
      end

      guard_result = ScanSolo::Cadence::TemplateAvailabilityGuard.check(enrollment: enrollment, attempt: locked_attempt)
      if guard_result.blocked?
        ScanSolo::Cadence::AttemptEvidenceRecorder.record_skipped!(locked_attempt)
        next
      end

      send_attempt!(locked_attempt, enrollment)
    end
  end

  def self.send_attempt!(attempt, enrollment)
    send_result = ScanSolo::Messaging::NativeTemplateSender.call(
      conversation: enrollment.opportunity.conversation,
      template_reference: attempt.template_reference,
      origin: 'cadence'
    )
    ScanSolo::Cadence::AttemptEvidenceRecorder.record_sent!(attempt, message: send_result.message)
  rescue StandardError => e
    Rails.logger.error("ScanSolo::CadenceDueAttemptJob failed to send attempt #{attempt.id}: #{e.message}")
    ScanSolo::Cadence::AttemptEvidenceRecorder.record_failed!(attempt)
  end
end
