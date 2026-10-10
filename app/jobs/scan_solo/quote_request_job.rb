# RF-12: requests the quote of a concluded qualification off the AI turn,
# enqueued by ScanSolo::LeadState::CompletionService only after every open
# transaction commits. The service revalidates eligibility in the database.
#
# RF-18 case A: a failure is retried 3 times, 1, 5 and 15 minutes after each
# failed attempt (4 attempts in total). A retry reuses the request left
# without `request_message_id`, so it never opens a 2nd request or thread.
# Once exhausted, and only while no request message exists, the failure goes
# to ScanSolo::Quote::DeliveryFailureService (private note + audit). Any other
# exhausted failure (no request opened, or the customer notice after the
# e-mail) goes to the exception tracker.
class ScanSolo::QuoteRequestJob < ApplicationJob
  WAITS = [1.minute, 5.minutes, 15.minutes].freeze

  queue_as :medium

  retry_on StandardError, attempts: WAITS.size + 1, wait: ->(executions) { WAITS.fetch(executions - 1) } do |job, error|
    quote_request = ScanSolo::QuoteRequest.find_by(opportunity_id: job.arguments.first)
    if quote_request.nil? || quote_request.request_message_id.present?
      ChatwootExceptionTracker.new(error).capture_exception
    else
      ScanSolo::Quote::DeliveryFailureService.call(opportunity: quote_request.opportunity, reason: error.class.name)
    end
  end

  def perform(opportunity_id)
    ScanSolo::Quote::RequestService.call(opportunity: ScanSolo::PipelineOpportunity.find(opportunity_id))
  end
end
