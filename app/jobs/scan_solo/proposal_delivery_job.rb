# RF-11 / RNF-01: delivers an approved proposal by e-mail after the approval
# transaction commits, so the e-mail is never created inside it.
class ScanSolo::ProposalDeliveryJob < ApplicationJob
  queue_as :medium

  def perform(proposal_version_id)
    ScanSolo::Proposal::DeliveryService.call(proposal_version: ScanSolo::ProposalVersion.find(proposal_version_id))
  end
end
