# RF-05 / RF-06 / RNF-06: the rejection of the current proposal version with a
# reason (the controller refuses a blank one, CT-03). Under the quote
# request's and the version's row locks: a non-current version raises
# `not_current_version`; anything but `awaiting_approval` raises
# `not_awaiting_approval`. Otherwise the version becomes `rejected` with
# `rejected_at`/`rejected_by`/`rejection_reason`, the quote request goes back
# to `awaiting_reply` (a new CT-04 block on the same thread generates the next
# version) and 1 `proposal.rejected` audit is recorded. A rejected version is
# never delivered.
class ScanSolo::Proposal::RejectService
  def self.call(proposal_version:, actor:, reason:)
    new(proposal_version: proposal_version, actor: actor, reason: reason).call
  end

  def initialize(proposal_version:, actor:, reason:)
    @proposal_version = proposal_version
    @actor = actor
    @reason = reason.strip
  end

  def call
    ActiveRecord::Base.transaction do
      quote_request.lock!
      proposal_version.lock!
      raise CustomExceptions::ScanSolo::ProposalActionRejected, 'not_current_version' unless proposal_version.is_current?
      raise CustomExceptions::ScanSolo::ProposalActionRejected, 'not_awaiting_approval' unless proposal_version.awaiting_approval?

      reject!
    end

    proposal_version
  end

  private

  attr_reader :proposal_version, :actor, :reason

  def reject!
    proposal_version.update!(status: :rejected, rejected_at: Time.current, rejected_by: actor, rejection_reason: reason)
    quote_request.update!(status: :awaiting_reply)
    ScanSolo::AuditLogger.record!(
      subject: proposal_version.proposal.opportunity, event_type: 'proposal.rejected', actor: actor,
      correlation_id: proposal_version.audit_correlation_id, payload: { proposal_version_id: proposal_version.id, reason: reason }
    )
  end

  def quote_request
    proposal_version.quote_request
  end
end
