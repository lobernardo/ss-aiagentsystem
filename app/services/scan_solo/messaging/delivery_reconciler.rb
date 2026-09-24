# RF-27/RF-41, CT-09: turns the native delivery state of a ScanSolo template
# message into evidence on the record that sent it -- a `dispatched`
# ScanSolo::CadenceAttempt (by `message_id`) or a not-yet-sent
# ScanSolo::ProposalVersion (by `sent_message_id`).
#
# A WhatsApp message counts as accepted once the provider gave it a
# `source_id` without a `failed` status; a non-WhatsApp (test) inbox counts
# a persisted non-failed message as accepted. A `failed` native message
# stores its `external_error`. Anything else is still pending and changes
# nothing. Idempotent: only `dispatched` attempts and unsent/unfailed
# versions are touched, under a row lock.
#
# An accepted proposal version becomes `sent` and runs
# ScanSolo::Proposal::SuccessHandler (stage -> proposta_enviada); a failed
# one becomes `failed` with the external error and the stage is untouched.
class ScanSolo::Messaging::DeliveryReconciler
  def self.call(message:)
    new(message: message).call
  end

  def initialize(message:)
    @message = message
  end

  def call
    return if outcome.nil?

    ScanSolo::CadenceAttempt.dispatched.where(message_id: message.id).find_each { |attempt| reconcile_attempt(attempt) }
    ScanSolo::ProposalVersion.where(sent_message_id: message.id).find_each { |version| reconcile_version(version) }
  end

  private

  attr_reader :message

  def outcome
    return :failed if message.failed?
    return :accepted if !message.inbox.channel.is_a?(Channel::Whatsapp) || message.source_id.present?

    nil
  end

  def reconcile_attempt(attempt)
    attempt.with_lock do
      next unless attempt.dispatched?

      if outcome == :accepted
        ScanSolo::Cadence::AttemptEvidenceRecorder.record_sent!(attempt)
      else
        ScanSolo::Cadence::AttemptEvidenceRecorder.record_failed!(attempt, external_error: external_error)
      end
    end
  end

  def reconcile_version(version)
    version.with_lock do
      next if version.sent? || version.failed?

      if outcome == :accepted
        version.update!(status: :sent)
        ScanSolo::Proposal::SuccessHandler.call(proposal_version: version)
      else
        version.update!(status: :failed, failure_reason: external_error)
      end
    end
  end

  def external_error
    message.external_error.presence || 'failed'
  end
end
