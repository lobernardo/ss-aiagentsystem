# RF-12: requests the quote of a concluded qualification off the AI turn,
# enqueued by ScanSolo::LeadState::CompletionService only after every open
# transaction commits. The service revalidates eligibility in the database.
class ScanSolo::QuoteRequestJob < ApplicationJob
  queue_as :medium

  def perform(opportunity_id)
    ScanSolo::Quote::RequestService.call(opportunity: ScanSolo::PipelineOpportunity.find(opportunity_id))
  end
end
