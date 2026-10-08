# RF-04 / RNF-02 / RNF-06: the explicit human approval of the current proposal
# version, always required (`require_proposal_approval` is ignored). Under the
# version's row lock: an `approved`/`sent` version returns as is (idempotent,
# no audit, no delivery); a non-current one raises `not_current_version`;
# anything but `awaiting_approval` raises `not_awaiting_approval`. Otherwise
# the version becomes `approved` with `approved_at`/`approved_by`, 1
# `proposal.approved` audit is recorded and, after the commit, the e-mail
# delivery (RF-11) is enqueued.
class ScanSolo::Proposal::ApproveService
  def self.call(proposal_version:, actor:)
    new(proposal_version: proposal_version, actor: actor).call
  end

  def initialize(proposal_version:, actor:)
    @proposal_version = proposal_version
    @actor = actor
  end

  def call
    proposal_version.with_lock do
      next if proposal_version.approved? || proposal_version.sent?
      raise CustomExceptions::ScanSolo::ProposalActionRejected, 'not_current_version' unless proposal_version.is_current?
      raise CustomExceptions::ScanSolo::ProposalActionRejected, 'not_awaiting_approval' unless proposal_version.awaiting_approval?

      approve!
    end

    proposal_version
  end

  private

  attr_reader :proposal_version, :actor

  def approve!
    proposal_version.update!(status: :approved, approved_at: Time.current, approved_by: actor)
    ScanSolo::AuditLogger.record!(
      subject: proposal_version.proposal.opportunity, event_type: 'proposal.approved', actor: actor,
      correlation_id: proposal_version.audit_correlation_id, payload: { proposal_version_id: proposal_version.id }
    )
    version_id = proposal_version.id
    ActiveRecord.after_all_transactions_commit { ScanSolo::ProposalDeliveryJob.perform_later(version_id) }
  end
end
