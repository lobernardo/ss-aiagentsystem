# CT-07 / RF-39 / RF-41: the single entry point of the negotiation
# notification. Every adapter of `adapters` receives the identical payload
# and answers a Result; a failure or an exception records
# `negotiation.notification_failed` and goes to the tracker, never
# propagating (the negotiation is never undone). A success records
# `negotiation.notification_sent`. Adding or swapping a channel only changes
# ADAPTERS.
class ScanSolo::Notifications::Publisher
  Result = Data.define(:success, :reason) do
    def success?
      success
    end
  end

  ADAPTERS = [ScanSolo::Notifications::EmailAdapter].freeze

  def self.call(event:, payload:, adapters: ADAPTERS)
    opportunity = ScanSolo::PipelineOpportunity.find(payload[:opportunity_id])
    adapters.each { |adapter| publish(adapter, event, payload, opportunity) }
  end

  def self.publish(adapter, event, payload, opportunity)
    result = adapter.call(event: event, payload: payload)
    raise CustomExceptions::ScanSolo::NegotiationNotificationFailed, result.reason unless result.success?

    audit!(opportunity, payload, 'negotiation.notification_sent', adapter: adapter.name)
  rescue StandardError => e
    audit!(opportunity, payload, 'negotiation.notification_failed', adapter: adapter.name, reason: e.message)
    ChatwootExceptionTracker.new(e, account: opportunity.account).capture_exception
  end

  def self.audit!(opportunity, payload, event_type, **audit_payload)
    ScanSolo::AuditLogger.record!(subject: opportunity, event_type: event_type, correlation_id: payload[:correlation_id], payload: audit_payload)
  end
  private_class_method :publish, :audit!
end
