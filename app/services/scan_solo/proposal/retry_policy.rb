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
# CT-10 / RF-32: a failure after the generate callback applied is a delivery
# failure (download or WhatsApp). Its retry redelivers through
# ScanSolo::Proposal::DeliveryService with the stored PDF -- no Make request,
# so no retry count nor dead letter applies.
class ScanSolo::Proposal::RetryPolicy
  class UnsafeRetryError < StandardError; end
  class ReprocessConfirmationRequiredError < StandardError; end

  SAFE_RETRYABLE_REASONS = %w[timeout network_error provider_unavailable].freeze

  def self.retryable?(proposal_version)
    proposal_version.failed? && (delivery_stage?(proposal_version) || SAFE_RETRYABLE_REASONS.include?(proposal_version.failure_reason))
  end

  # `value` is written only by a successful generate callback (RF-26), so a
  # failure after it can only come from the delivery.
  def self.delivery_stage?(proposal_version)
    proposal_version.generate_callback_applied_at.present? && proposal_version.value.present?
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
    return retry_delivery! if self.class.delivery_stage?(proposal_version)
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

  def retry_delivery!
    ScanSolo::AuditLogger.record!(
      subject: proposal_version, event_type: 'proposal.retry_requested', actor: actor, correlation_id: proposal_version.audit_correlation_id,
      payload: { failure_reason: proposal_version.failure_reason, operation: 'delivery' }
    )
    ScanSolo::Proposal::DeliveryService.call(proposal_version: proposal_version, redeliver: true)
    proposal_version.reload
  end

  def retry_generate!(new_correlation_id)
    retry_count = previous_retry_count + 1
    proposal_version.update!(
      status: :generating, failure_reason: nil, generate_callback_applied_at: nil, generate_correlation_id: new_correlation_id
    )
    provider.request_generation(proposal_version: proposal_version, correlation_id: new_correlation_id, actor: actor, retry_count: retry_count)
  end
end
