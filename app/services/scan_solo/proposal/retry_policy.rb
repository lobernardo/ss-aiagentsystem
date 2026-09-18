# RF-81: retries only safely-retryable proposal-integration failures --
# ones where no partial/unknown side effect occurred -- and never
# auto-retries an operation left in an unsafe/ambiguous side-effect state.
# A retry always reuses the same ScanSolo::ProposalVersion row (a fresh
# correlation id, but the same version), so it never duplicates a
# proposal/send; an unsafe failure raises instead, leaving the version
# exactly as it was for manual review.
class ScanSolo::Proposal::RetryPolicy
  class UnsafeRetryError < StandardError; end

  SAFE_RETRYABLE_REASONS = %w[timeout network_error provider_unavailable].freeze

  def self.retryable?(proposal_version)
    proposal_version.failed? && SAFE_RETRYABLE_REASONS.include?(proposal_version.failure_reason)
  end

  def self.retry!(proposal_version:, provider: ScanSolo::Proposal::MockProvider, conversation: nil, actor: nil)
    new(proposal_version: proposal_version, provider: provider, conversation: conversation, actor: actor).retry!
  end

  def initialize(proposal_version:, provider:, conversation: nil, actor: nil)
    @proposal_version = proposal_version
    @provider = provider
    @conversation = conversation
    @actor = actor
  end

  def retry!
    raise UnsafeRetryError, proposal_version.failure_reason unless self.class.retryable?(proposal_version)

    send_stage? ? retry_send! : retry_generate!

    proposal_version.reload
  end

  private

  attr_reader :proposal_version, :provider, :conversation, :actor

  # A failure with a commercial value already present can only have
  # happened on the send step -- generate is the sole writer of `value`
  # (RF-76), so its presence proves generate already succeeded once.
  def send_stage?
    proposal_version.value.present?
  end

  def retry_generate!
    new_correlation_id = SecureRandom.uuid
    proposal_version.update!(
      status: :generating, failure_reason: nil, generate_callback_applied_at: nil, generate_correlation_id: new_correlation_id
    )
    provider.request_generation(proposal_version: proposal_version, correlation_id: new_correlation_id)
  end

  def retry_send!
    new_correlation_id = SecureRandom.uuid
    restored_status = proposal_version.approved_at.present? ? :approved : :generated
    proposal_version.update!(
      status: restored_status, failure_reason: nil, send_callback_applied_at: nil, send_correlation_id: new_correlation_id
    )
    provider.request_send(proposal_version: proposal_version, correlation_id: new_correlation_id, conversation: conversation, actor: actor)
  end
end
