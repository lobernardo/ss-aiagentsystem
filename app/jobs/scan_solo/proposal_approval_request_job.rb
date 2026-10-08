# RF-01 / RF-02 / RNF-01 / RNF-03: stores the PDF and requests the
# commercial approval after the generate callback transaction commits, so the
# download and the e-mail never run inside it. No cron involved.
class ScanSolo::ProposalApprovalRequestJob < ApplicationJob
  queue_as :medium

  def perform(proposal_version_id)
    ScanSolo::Proposal::ApprovalRequestService.call(proposal_version: ScanSolo::ProposalVersion.find(proposal_version_id))
  end
end
