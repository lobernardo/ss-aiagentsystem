# Escalação comercial RF-09/RF-23/CT-03 + escalação filtrada RF-01/RF-03/
# RF-04/RF-05/RF-08/RF-11/RF-12/CT-01: the single place that writes the
# commercial escalation mark and `email_redirect_count`. Runs inside the
# caller's transaction (the attempt savepoint), so a rolled-back turn leaves
# no mark, no counter change and no event. `lock!` serializes concurrent turns
# on the same opportunity, so every decision is taken on the committed row.
#
# Every commercial request goes through ScanSolo::Commercial::EscalationGate,
# with 1 decision per turn (`correlation_id`): a 2nd call in the same turn
# returns the decision already recorded (`commercial.escalated` or
# `commercial.escalation_refused`) without re-deciding, so a counter just
# incremented is never read as insistence.
# - approved: overwrites the mark and records 1 `commercial.escalated`; only
#   the first escalation (opportunity not escalated before) publishes the
#   commercial notice e-mail, after commit.
# - refused: records 1 `commercial.escalation_refused` (no phone), increments
#   the counter only on `primeiro_pedido_email`, publishes nothing and never
#   raises; returns the CT-01 refusal hash.
class ScanSolo::Commercial::EscalationService
  EVENT = 'commercial.escalated'.freeze
  REFUSED_EVENT = 'commercial.escalation_refused'.freeze

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
    return result if turn_event(EVENT)

    refused = turn_event(REFUSED_EVENT)
    return refusal_result(refused.payload['refusal']) if refused

    decision = decide
    decision == :approved ? escalate! : refuse!(decision)
  end

  private

  attr_reader :opportunity, :reason, :turn

  def turn_event(event_type)
    ScanSolo::AuditEvent.find_by(subject: opportunity, event_type: event_type, correlation_id: turn.correlation_id)
  end

  def decide
    ScanSolo::Commercial::EscalationGate.decide(
      stage: opportunity.stage, quote_sent: ScanSolo::Commercial::EscalationGate.quote_sent?(opportunity),
      email_redirect_count: opportunity.email_redirect_count, commercial_request: true,
      previously_escalated: opportunity.escalated_to_commercial_at.present?
    )
  end

  def escalate!
    first = !opportunity.escalated_to_commercial?
    opportunity.update!(escalated_to_commercial_at: Time.current, escalation_reason: reason)
    record_audit!(EVENT, reason: reason)
    publish_after_commit if first

    result
  end

  def refuse!(decision)
    opportunity.update!(email_redirect_count: opportunity.email_redirect_count + 1) if decision == :primeiro_pedido_email
    record_audit!(REFUSED_EVENT, refusal: decision.to_s, email_redirect_count: opportunity.email_redirect_count, reason: reason)

    refusal_result(decision.to_s)
  end

  # CT-03: no phone in the payload.
  def record_audit!(event_type, **payload)
    ScanSolo::AuditLogger.record!(
      subject: opportunity, event_type: event_type, correlation_id: turn.correlation_id,
      payload: payload.merge(conversation_id: opportunity.conversation_id, message_id: turn.message_id, stage: opportunity.stage)
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

  def refusal_result(refusal)
    { escalated: false, refusal: refusal, email_redirect_count: opportunity.email_redirect_count }
  end
end
