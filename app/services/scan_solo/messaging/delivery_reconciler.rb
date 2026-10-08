# RF-27/RF-41, CT-09: turns the native delivery state of a ScanSolo template
# message into evidence on the record that sent it -- a `dispatched`
# ScanSolo::CadenceAttempt (by `message_id`), a not-yet-sent
# ScanSolo::ProposalVersion (by `sent_message_id`, the proposal e-mail) or the
# version's WhatsApp notice (by `notice_message_id`).
#
# A WhatsApp or e-mail message counts as accepted only once the native send
# gave it a `source_id` without a `failed` status (RF-13); another (test)
# inbox counts a persisted non-failed message as accepted. A `failed` native
# message stores its `external_error`. Anything else is still pending and
# changes nothing. Idempotent: only `dispatched` attempts and unsent/unfailed
# versions are touched, under a row lock.
#
# RF-13: an accepted proposal e-mail makes the version `sent`, is audited as
# `proposal.sent` with the quote request correlation id (RNF-06) and runs
# ScanSolo::Proposal::SuccessHandler (stage -> proposta_enviada, then the
# WhatsApp notice after the commit); a failed one becomes `failed` with the
# external error and 1 `proposal.delivery_failed` audit, the stage untouched
# (RF-14). A `sent` version whose e-mail later fails becomes `failed` with 1
# `proposal.delivery_failed_after_sent` audit, keeping the stage and the
# enrollment; a `failed` version is never touched again.
#
# RF-14: a failed WhatsApp notice never changes the version status; it stores
# `notice_failure_reason` and records 1 `proposal.lead_notice_failed` audit
# per failure (a new notice clears the reason, LeadNoticeService).
#
# RF-08: a failed manual-lead initial template has no record of its own; it
# is audited once per message as `pipeline.manual_lead_template_failed` on
# the conversation's opportunity, for the opportunity detail (UI-04).
class ScanSolo::Messaging::DeliveryReconciler
  MANUAL_LEAD_FAILED_EVENT = 'pipeline.manual_lead_template_failed'.freeze
  SOURCE_ID_CHANNELS = [Channel::Whatsapp, Channel::Email].freeze

  def self.call(message:)
    new(message: message).call
  end

  def initialize(message:)
    @message = message
  end

  def call
    return if outcome.nil?

    ScanSolo::CadenceAttempt.dispatched.where(message_id: message.id).find_each { |attempt| reconcile_attempt(attempt) }
    reconcile_proposal_versions
    record_manual_lead_failure if outcome == :failed && message.additional_attributes.to_h['scansolo_origin'] == 'manual_lead'
  end

  private

  attr_reader :message

  def outcome
    return :failed if message.failed?
    return :accepted if message.source_id.present? || SOURCE_ID_CHANNELS.none? { |klass| message.inbox.channel.is_a?(klass) }

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

  def reconcile_proposal_versions
    ScanSolo::ProposalVersion.where(sent_message_id: message.id).find_each { |version| reconcile_version(version) }
    return unless outcome == :failed

    ScanSolo::ProposalVersion.where(notice_message_id: message.id).find_each { |version| record_notice_failure(version) }
  end

  def reconcile_version(version)
    version.with_lock do
      next if version.failed?

      if version.sent?
        fail_version!(version, 'proposal.delivery_failed_after_sent') if outcome == :failed
      elsif outcome == :accepted
        version.update!(status: :sent)
        ScanSolo::AuditLogger.record!(
          subject: version.proposal.opportunity, event_type: 'proposal.sent', correlation_id: version.audit_correlation_id,
          payload: { proposal_version_id: version.id, message_id: message.id }
        )
        ScanSolo::Proposal::SuccessHandler.call(proposal_version: version)
      else
        fail_version!(version, 'proposal.delivery_failed')
      end
    end
  end

  def fail_version!(version, event_type)
    version.update!(status: :failed, failure_reason: external_error)
    ScanSolo::AuditLogger.record!(
      subject: version.proposal.opportunity, event_type: event_type, correlation_id: version.audit_correlation_id,
      payload: { proposal_version_id: version.id, message_id: message.id, reason: external_error }
    )
  end

  def record_notice_failure(version)
    version.with_lock do
      next if version.notice_failure_reason == external_error

      version.update!(notice_failure_reason: external_error)
      ScanSolo::AuditLogger.record!(
        subject: version.proposal.opportunity, event_type: 'proposal.lead_notice_failed', correlation_id: version.audit_correlation_id,
        payload: { proposal_version_id: version.id, message_id: message.id, reason: external_error }
      )
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
