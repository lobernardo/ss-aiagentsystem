# RF-14 (b) / RNF-05: opens the fixed update window of a sent quote request.
#
# Called after commit by the lead state Writer (a field really changed) and by
# the listener (incoming attachment, location or map URL). The first change
# after the last e-mail sent opens a 10-minute window and enqueues
# ScanSolo::QuoteRequestUpdateJob for its end; later changes neither restart
# nor extend it. ScanSolo::Quote::UpdateService closes the window when the job
# runs, so a change after that opens a new one. Under the request lock, 2
# concurrent calls enqueue 1 job.
class ScanSolo::Quote::UpdateScheduler
  WINDOW = 10.minutes

  def self.call(opportunity:)
    quote_request = opportunity.quote_request
    return unless quote_request&.request_message_id.present? && quote_request.open?

    quote_request.with_lock do
      next if quote_request.update_window_ends_at.present?

      quote_request.update!(update_window_ends_at: Time.current + WINDOW)
      ScanSolo::QuoteRequestUpdateJob.set(wait_until: quote_request.update_window_ends_at).perform_later(quote_request.id)
    end
  end
end
