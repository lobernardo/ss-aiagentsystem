# CT-07 / RF-39 / RF-41: the single entry point of the negotiation
# notification. Every adapter of `adapters` receives the identical payload
# and answers a Result; a failure or an exception records
# `negotiation.notification_failed` and goes to the tracker, never
# propagating (the negotiation is never undone). A success records
# `negotiation.notification_sent`. Adding or swapping a channel only changes
# ADAPTERS.
#
# RF-23 (scansolo-proposta-aprovacao-email): published at most once per
# `correlation_id`. The claim is a `negotiation.notification_claimed`
# AuditEvent written under the opportunity lock and committed before any
# adapter runs (adapters deliver outside the transaction, RNF-01); an already
# claimed correlation id publishes nothing, even after an adapter failure.
class ScanSolo::Notifications::Publisher
  Result = Data.define(:success, :reason) do
    def success?
      success
    end
  end

  ADAPTERS = [ScanSolo::Notifications::EmailAdapter].freeze
  CLAIM_EVENT = 'negotiation.notification_claimed'.freeze

  def self.call(event:, payload:, adapters: ADAPTERS)
    opportunity = ScanSolo::PipelineOpportunity.find(payload[:opportunity_id])
    return unless claim!(opportunity, payload)

    adapters.each { |adapter| publish(adapter, event, payload, opportunity) }
  end

  def self.claim!(opportunity, payload)
    opportunity.with_lock do
      next false if ScanSolo::AuditEvent.exists?(subject: opportunity, event_type: CLAIM_EVENT, correlation_id: payload[:correlation_id])

      audit!(opportunity, payload, CLAIM_EVENT)
      true
    end
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
  private_class_method :claim!, :publish, :audit!
end
