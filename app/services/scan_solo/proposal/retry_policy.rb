# RF-40: retries only safely-retryable proposal-integration failures --
# ones where no partial/unknown side effect occurred -- and never
# auto-retries an operation left in an unsafe/ambiguous side-effect state.
# A retry always reuses the same ScanSolo::ProposalVersion row with a fresh
# correlation id, so it never duplicates a proposal/send; an unsafe failure
# raises instead, leaving the version exactly as it was for manual review.
#
# Each retry carries the operation's retry count forward (+1) onto the new
# ScanSolo::MakeRequest. Once the count reaches
# ScanSolo::MakeRequest::DEAD_LETTER_RETRY_THRESHOLD the failed operation is
# a dead letter and only an explicit administrator reprocess
# (`confirm_reprocess: true`) may retry it again. Every accepted request is
# audited as `proposal.retry_requested` or `proposal.reprocess_requested`.
#
# RF-15 (replaces OC/CT-10): every retry acts on the same version, never a new
# one (RF-07), by the failure's cause:
#   (a) a version that was approved failed on the lead e-mail delivery -- it is
#       redelivered by ScanSolo::Proposal::DeliveryService with the stored PDF
#       on the same proposal thread; the WhatsApp notice only follows the new
#       e-mail's `source_id` (RF-13) and only if none was accepted;
#   (c) a PDF download/checksum failure -- the PDF is fetched again by
#       ScanSolo::Proposal::ApprovalRequestService, which returns the version to
#       `awaiting_approval` and requests the approval (CT-05);
#   (b) a safely-retryable generate failure -- regenerated through Make, as
#       below.
# (a) and (c) create no Make request, so no retry count nor dead letter applies.
class ScanSolo::Proposal::RetryPolicy
  class UnsafeRetryError < StandardError; end
  class ReprocessConfirmationRequiredError < StandardError; end

  SAFE_RETRYABLE_REASONS = %w[timeout network_error provider_unavailable].freeze
  ARTIFACT_REASONS = ScanSolo::Proposal::ApprovalRequestService::REDOWNLOAD_REASONS

  def self.retryable?(proposal_version)
    proposal_version.failed? && (
      proposal_version.approved_at.present? ||
      ARTIFACT_REASONS.include?(proposal_version.failure_reason) ||
      SAFE_RETRYABLE_REASONS.include?(proposal_version.failure_reason)
    )
  end

  def self.retry!(proposal_version:, confirm_reprocess: false, provider: nil, actor: nil)
    new(proposal_version: proposal_version, confirm_reprocess: confirm_reprocess, provider: provider, actor: actor).retry!
  end

  def initialize(proposal_version:, confirm_reprocess:, provider:, actor:)
    @proposal_version = proposal_version
    @confirm_reprocess = confirm_reprocess
    @provider = provider
    @actor = actor
  end

  def retry!
    unless self.class.retryable?(proposal_version)
      raise UnsafeRetryError, "failure reason #{proposal_version.failure_reason.inspect} is not safely retryable"
    end
    return retry_email_delivery! if proposal_version.approved_at.present?
    return retry_artifact_download! if ARTIFACT_REASONS.include?(proposal_version.failure_reason)
    raise ReprocessConfirmationRequiredError, 'dead-lettered operation requires confirm_reprocess: true' if dead_letter? && !confirm_reprocess

    @provider ||= ScanSolo::Proposal::Integration.provider!
    new_correlation_id = SecureRandom.uuid
    audit!(new_correlation_id)
    retry_generate!(new_correlation_id)

    proposal_version.reload
  end

  private

  attr_reader :proposal_version, :confirm_reprocess, :provider, :actor

  def previous_retry_count
    @previous_retry_count ||= proposal_version.make_request&.retry_count.to_i
  end

  def dead_letter?
    previous_retry_count >= ScanSolo::MakeRequest::DEAD_LETTER_RETRY_THRESHOLD
  end

  # RF-50: one audit event per administrator retry/reprocess request.
  def audit!(new_correlation_id)
    ScanSolo::AuditLogger.record!(
      subject: proposal_version, event_type: dead_letter? ? 'proposal.reprocess_requested' : 'proposal.retry_requested',
      actor: actor, correlation_id: new_correlation_id,
      payload: {
        failure_reason: proposal_version.failure_reason, retry_count: previous_retry_count + 1, operation: 'generate'
      }
    )
  end

  def retry_email_delivery!
    audit_without_make!('email_delivery')
    ScanSolo::Proposal::DeliveryService.call(proposal_version: proposal_version, redeliver: true)
    proposal_version.reload
  end

  def retry_artifact_download!
    audit_without_make!('artifact_download')
    ScanSolo::Proposal::ApprovalRequestService.call(proposal_version: proposal_version, redownload: true)
    proposal_version.reload
  end

  def audit_without_make!(operation)
    ScanSolo::AuditLogger.record!(
      subject: proposal_version, event_type: 'proposal.retry_requested', actor: actor, correlation_id: proposal_version.audit_correlation_id,
      payload: { failure_reason: proposal_version.failure_reason, operation: operation }
    )
  end

  def retry_generate!(new_correlation_id)
    retry_count = previous_retry_count + 1
    proposal_version.update!(
      status: :generating, failure_reason: nil, generate_callback_applied_at: nil, generate_correlation_id: new_correlation_id
    )
    provider.request_generation(proposal_version: proposal_version, correlation_id: new_correlation_id, actor: actor, retry_count: retry_count)
  end
end
