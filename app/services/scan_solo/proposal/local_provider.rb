# RF-02, CT-01: the local proposal provider (selected by
# ScanSolo::Proposal::Integration while `SCANSOLO_GOTENBERG_URL` is set). It
# only enqueues ScanSolo::ProposalLocalGenerationJob once every open
# transaction commits -- no HTTP, render or version write here; the job
# (ScanSolo::Proposal::LocalGenerationService) does the work. There is no
# `request_send`: delivery goes through ScanSolo::Proposal::DeliveryService.
class ScanSolo::Proposal::LocalProvider
  def self.request_generation(proposal_version:, correlation_id:, **)
    ActiveRecord.after_all_transactions_commit do
      ScanSolo::ProposalLocalGenerationJob.perform_later(proposal_version.id, correlation_id)
    end
  end
end
