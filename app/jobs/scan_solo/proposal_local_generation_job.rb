# CT-02 / RF-11 / RNF-03: generates a proposal version's PDF locally. A
# Gotenberg timeout, connection error or 5xx is retried 30 s and 2 min later
# (3 attempts in total), each attempt rechecking the version (RF-03); once
# exhausted the version fails with `provider_unavailable`.
class ScanSolo::ProposalLocalGenerationJob < ApplicationJob
  RETRY_WAITS = [30.seconds, 2.minutes].freeze

  queue_as :medium

  retry_on CustomExceptions::ScanSolo::GotenbergUnavailable, attempts: 3,
                                                             wait: ->(executions) { RETRY_WAITS.fetch(executions - 1) } do |job, _error|
    ScanSolo::Proposal::LocalGenerationService.exhausted!(proposal_version_id: job.arguments[0], correlation_id: job.arguments[1])
  end

  def perform(proposal_version_id, correlation_id)
    ScanSolo::Proposal::LocalGenerationService.call(proposal_version_id: proposal_version_id, correlation_id: correlation_id)
  end
end
