# RF-73/RF-77/RF-79/RF-80: `proposal.send` cannot execute without a prior
# successful `proposal.generate` result for the same version (RF-73 second
# half), is rejected against a stale (non-current) version (RF-77), and
# blocks on a missing approval when ScanSolo::ProposalVersion#approval_
# required? is true (RF-78). The actual transport attempt and its
# idempotent callback handling live entirely in
# ScanSolo::Proposal::CallbackHandler (via the registered provider) --
# this service never itself marks the version `sent` (RF-79).
class ScanSolo::Proposal::SendService
  def self.call(proposal_version:, correlation_id:, conversation:, actor: nil, provider: ScanSolo::Proposal::MockProvider)
    new(
      proposal_version: proposal_version, correlation_id: correlation_id, conversation: conversation, actor: actor, provider: provider
    ).call
  end

  def initialize(proposal_version:, correlation_id:, conversation:, actor: nil, provider: ScanSolo::Proposal::MockProvider)
    @proposal_version = proposal_version
    @correlation_id = correlation_id
    @conversation = conversation
    @actor = actor
    @provider = provider
  end

  def call
    reject_unless_current!
    reject_unless_generated!
    reject_unless_approved!

    proposal_version.update!(send_correlation_id: correlation_id, send_requested_at: Time.current) if proposal_version.send_correlation_id.blank?

    provider.request_send(proposal_version: proposal_version, correlation_id: correlation_id, conversation: conversation, actor: actor)

    proposal_version.reload
  end

  private

  attr_reader :proposal_version, :correlation_id, :conversation, :actor, :provider

  def reject_unless_current!
    return if proposal_version.is_current?

    reject!('proposal version is not the current version')
  end

  def reject_unless_generated!
    return if proposal_version.generated? || proposal_version.approved? || proposal_version.sent?

    reject!('proposal.send requires a prior successful proposal.generate result for this version')
  end

  def reject_unless_approved!
    return unless proposal_version.approval_required?
    return if proposal_version.approved_at.present?

    reject!('proposal approval is required before send')
  end

  def reject!(message)
    proposal_version.errors.add(:base, message)
    raise ActiveRecord::RecordInvalid, proposal_version
  end
end
