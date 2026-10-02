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
#
# RF-08: a failed manual-lead initial template has no record of its own; it
# is audited once per message as `pipeline.manual_lead_template_failed` on
# the conversation's opportunity, for the opportunity detail (UI-04).
class ScanSolo::Messaging::DeliveryReconciler
  MANUAL_LEAD_FAILED_EVENT = 'pipeline.manual_lead_template_failed'.freeze

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
    record_manual_lead_failure if outcome == :failed && message.additional_attributes.to_h['scansolo_origin'] == 'manual_lead'
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

  def record_manual_lead_failure
    opportunity = ScanSolo::PipelineOpportunity.find_by!(conversation_id: message.conversation_id)
    opportunity.with_lock do
      next if ScanSolo::AuditEvent.where(subject: opportunity, event_type: MANUAL_LEAD_FAILED_EVENT)
                                  .exists?(['payload @> ?', { message_id: message.id }.to_json])

      ScanSolo::AuditLogger.record!(
        subject: opportunity, event_type: MANUAL_LEAD_FAILED_EVENT, correlation_id: SecureRandom.uuid,
        payload: { message_id: message.id, external_error: external_error }
      )
    end
  end

  def external_error
    message.external_error.presence || 'failed'
  end
end
