# RF-29 / RNF-01: delivers a generated proposal after the callback
# transaction commits, so the PDF download and the WhatsApp message never run
# inside it.
class ScanSolo::ProposalDeliveryJob < ApplicationJob
  queue_as :medium

  def perform(proposal_version_id)
    ScanSolo::Proposal::DeliveryService.call(proposal_version: ScanSolo::ProposalVersion.find(proposal_version_id))
  end
end
