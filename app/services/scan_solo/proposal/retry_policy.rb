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
class ScanSolo::Proposal::RetryPolicy
  class UnsafeRetryError < StandardError; end
  class ReprocessConfirmationRequiredError < StandardError; end

  SAFE_RETRYABLE_REASONS = %w[timeout network_error provider_unavailable].freeze

  def self.retryable?(proposal_version)
    proposal_version.failed? && SAFE_RETRYABLE_REASONS.include?(proposal_version.failure_reason)
  end

  def self.retry!(proposal_version:, confirm_reprocess: false, provider: nil, conversation: nil, actor: nil)
    new(proposal_version: proposal_version, confirm_reprocess: confirm_reprocess, provider: provider, conversation: conversation,
        actor: actor).retry!
  end

  def initialize(proposal_version:, confirm_reprocess:, provider:, conversation:, actor:)
    @proposal_version = proposal_version
    @confirm_reprocess = confirm_reprocess
    @provider = provider || ScanSolo::Proposal::Integration.provider!
    @conversation = conversation
    @actor = actor
  end

  def retry!
    unless self.class.retryable?(proposal_version)
      raise UnsafeRetryError, "failure reason #{proposal_version.failure_reason.inspect} is not safely retryable"
    end
    raise ReprocessConfirmationRequiredError, 'dead-lettered operation requires confirm_reprocess: true' if dead_letter? && !confirm_reprocess

    new_correlation_id = SecureRandom.uuid
    audit!(new_correlation_id)
    send_stage? ? retry_send!(new_correlation_id) : retry_generate!(new_correlation_id)

    proposal_version.reload
  end

  private

  attr_reader :proposal_version, :confirm_reprocess, :provider, :conversation, :actor

  def previous_retry_count
    @previous_retry_count ||= proposal_version.make_request&.retry_count.to_i
  end

  def dead_letter?
    previous_retry_count >= ScanSolo::MakeRequest::DEAD_LETTER_RETRY_THRESHOLD
  end

  # A failure with a commercial value already present can only have
  # happened on the send step -- generate is the sole writer of `value`
  # (RF-76), so its presence proves generate already succeeded once.
  def send_stage?
    proposal_version.value.present?
  end

  # RF-50: one audit event per administrator retry/reprocess request.
  def audit!(new_correlation_id)
    ScanSolo::AuditLogger.record!(
      subject: proposal_version, event_type: dead_letter? ? 'proposal.reprocess_requested' : 'proposal.retry_requested',
      actor: actor, correlation_id: new_correlation_id,
      payload: {
        failure_reason: proposal_version.failure_reason, retry_count: previous_retry_count + 1, operation: send_stage? ? 'send' : 'generate'
      }
    )
  end

  def retry_generate!(new_correlation_id)
    retry_count = previous_retry_count + 1
    proposal_version.update!(
      status: :generating, failure_reason: nil, generate_callback_applied_at: nil, generate_correlation_id: new_correlation_id
    )
    provider.request_generation(proposal_version: proposal_version, correlation_id: new_correlation_id, actor: actor, retry_count: retry_count)
  end

  def retry_send!(new_correlation_id)
    retry_count = previous_retry_count + 1
    restored_status = proposal_version.approved_at.present? ? :approved : :generated
    proposal_version.update!(
      status: restored_status, failure_reason: nil, send_callback_applied_at: nil, send_correlation_id: new_correlation_id
    )
    provider.request_send(proposal_version: proposal_version, correlation_id: new_correlation_id, conversation: conversation, actor: actor,
                          retry_count: retry_count)
  end
end
