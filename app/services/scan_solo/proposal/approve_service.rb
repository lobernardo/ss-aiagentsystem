# RF-78: records an explicit human approval on the current proposal
# version. `proposal.send` (ScanSolo::Proposal::SendService) reads
# `approved_at` directly off the version to decide whether to block --
# this service's only job is to record that approval, never to decide
# whether it is required (that decision lives on
# ScanSolo::ProposalVersion#approval_required?, shared by both services).
class ScanSolo::Proposal::ApproveService
  def self.call(proposal_version:, correlation_id:, actor: nil)
    new(proposal_version: proposal_version, correlation_id: correlation_id, actor: actor).call
  end

  def initialize(proposal_version:, correlation_id:, actor: nil)
    @proposal_version = proposal_version
    @correlation_id = correlation_id
    @actor = actor
  end

  def call
    reject_unless_current!
    return proposal_version if proposal_version.approved_at.present?

    updates = { approved_at: Time.current, approved_by: actor }
    updates[:status] = :approved if proposal_version.generated?
    proposal_version.update!(updates)

    proposal_version
  end

  private

  attr_reader :proposal_version, :correlation_id, :actor

  def reject_unless_current!
    return if proposal_version.is_current?

    proposal_version.errors.add(:base, 'proposal version is not the current version')
    raise ActiveRecord::RecordInvalid, proposal_version
  end
end
