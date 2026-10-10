# RF-14 / RF-18: sends the update e-mail of a quote request at the end of its
# fixed update window (ScanSolo::Quote::UpdateService).
#
# RF-18 case A: like ScanSolo::QuoteRequestJob, a failure is retried 3 times,
# 1, 5 and 15 minutes after each failed attempt (4 attempts in total). A failed
# post releases its version claim, so a retry sends it once. Once exhausted,
# the failure goes to ScanSolo::Quote::DeliveryFailureService (private note +
# audit); no update message exists then, as a post that went through ends
# the retries (its version is claimed and becomes the comparison base).
class ScanSolo::QuoteRequestUpdateJob < ApplicationJob
  WAITS = ScanSolo::QuoteRequestJob::WAITS

  queue_as :medium

  retry_on StandardError, attempts: WAITS.size + 1, wait: ->(executions) { WAITS.fetch(executions - 1) } do |job, error|
    quote_request = ScanSolo::QuoteRequest.find(job.arguments.first)
    ScanSolo::Quote::DeliveryFailureService.call(opportunity: quote_request.opportunity, reason: error.class.name)
  end

  def perform(quote_request_id)
    ScanSolo::Quote::UpdateService.call(quote_request: ScanSolo::QuoteRequest.find(quote_request_id))
  end
end
