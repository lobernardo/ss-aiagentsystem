# Escalação comercial RF-09/RF-23/CT-03: the single place that writes the
# commercial escalation mark. Runs inside the caller's transaction (the
# attempt savepoint), so a rolled-back turn leaves no mark and no event.
# `lock!` serializes concurrent turns on the same opportunity, so the "first
# escalation" decision is taken on the committed row. At most 1 escalation per
# turn (`correlation_id`). Every escalation overwrites the mark and records 1
# `commercial.escalated` event; only the first one (opportunity not escalated
# before, per RF-11) publishes the commercial notice e-mail, after commit.
class ScanSolo::Commercial::EscalationService
  EVENT = 'commercial.escalated'.freeze

  def self.call(opportunity:, reason:, turn:)
    new(opportunity: opportunity, reason: reason, turn: turn).call
  end

  def initialize(opportunity:, reason:, turn:)
    @opportunity = opportunity
    @reason = reason
    @turn = turn
  end

  def call
    opportunity.lock!
    return result if ScanSolo::AuditEvent.exists?(subject: opportunity, event_type: EVENT, correlation_id: turn.correlation_id)

    first = !opportunity.escalated_to_commercial?
    opportunity.update!(escalated_to_commercial_at: Time.current, escalation_reason: reason)
    record_audit!
    publish_after_commit if first

    result
  end

  private

  attr_reader :opportunity, :reason, :turn

  # CT-03: no phone in the payload.
  def record_audit!
    ScanSolo::AuditLogger.record!(
      subject: opportunity, event_type: EVENT, correlation_id: turn.correlation_id,
      payload: { reason: reason, conversation_id: opportunity.conversation_id, message_id: turn.message_id, stage: opportunity.stage }
    )
  end

  def publish_after_commit
    ActiveRecord.after_all_transactions_commit do
      payload = ScanSolo::Notifications::NegotiationPayload.build(
        opportunity: opportunity.reload, trigger_message: turn.message, correlation_id: turn.correlation_id
      )
      ScanSolo::Notifications::Publisher.call(event: EVENT, payload: payload.merge(escalation_reason: reason))
    end
  end

  def result
    { escalated: true, reason: opportunity.escalation_reason, escalated_at: opportunity.escalated_to_commercial_at.iso8601 }
  end
end
