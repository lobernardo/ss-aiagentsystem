# RF-21 / CT-04: the legacy `POST .../proposals/:id/send`, kept only until the
# OC Phase 20 removal. It never emits `proposal.send` to Make: a non-current
# version raises `not_current_version`, a `sent` one `already_sent`, anything
# but `approved` `approval_required`; an `approved` version is handed to the
# same idempotent e-mail delivery as the approval (RF-11, RF-12), so an
# already delivered version gets no 2nd e-mail. Historical `proposal.send`
# callbacks are still accepted by ScanSolo::Proposal::CallbackHandler.
class ScanSolo::Proposal::SendService
  def self.call(proposal_version:, **)
    new(proposal_version: proposal_version).call
  end

  def initialize(proposal_version:)
    @proposal_version = proposal_version
  end

  def call
    raise CustomExceptions::ScanSolo::ProposalActionRejected, 'not_current_version' unless proposal_version.is_current?
    raise CustomExceptions::ScanSolo::ProposalActionRejected, 'already_sent' if proposal_version.sent?
    raise CustomExceptions::ScanSolo::ProposalActionRejected, 'approval_required' unless proposal_version.approved?

    ScanSolo::Proposal::DeliveryService.call(proposal_version: proposal_version)
    proposal_version.reload
  end

  private

  attr_reader :proposal_version
end
