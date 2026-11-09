# RF-35..RF-39, escalação comercial RF-13/RF-14/RF-19/RF-23: the only
# automatic path to `negociacao`. Runs inside the AI attempt's transaction
# (rolled back with it when the validator blocks):
# 1. from `proposta_enviada`, moves to `negociacao` through
#    ScanSolo::Pipeline::StageTransitionService with system authorization;
#    from `qualificado` or already in `negociacao`, no stage event (RF-35);
# 2. records `negotiation.requested` with the turn's correlation id and the
#    escalation reason;
# 3. with an `escalation_reason` (`negociacao`/`duvida_proposta`, published
#    commercial number present), escalates through
#    ScanSolo::Commercial::EscalationService, which publishes the commercial
#    notice only on the first escalation. The AI stays `ai_active`: no
#    handoff, no assignment, no cadence pause here.
# Without an `escalation_reason` (no published number, RF-19) there is no mark
# and, after the commit, the CT-07 notification goes through the replaceable
# ScanSolo::Notifications::Publisher as before (RF-37, RF-41); a failure
# there does not undo the negotiation (RF-39).
class ScanSolo::Negotiation::RequestService
  EVENT = 'negotiation.requested'.freeze

  def self.call(opportunity:, turn:, message:, escalation_reason:)
    new(opportunity: opportunity, turn: turn, message: message, escalation_reason: escalation_reason).call
  end

  def initialize(opportunity:, turn:, message:, escalation_reason:)
    @opportunity = opportunity
    @turn = turn
    @message = message
    @escalation_reason = escalation_reason
  end

  def call
    from_stage = opportunity.stage
    if opportunity.proposta_enviada?
      ScanSolo::Pipeline::StageTransitionService.new(opportunity: opportunity, target_stage: 'negociacao', authorized: true).call
    end

    ScanSolo::AuditLogger.record!(subject: opportunity, event_type: EVENT, correlation_id: turn.correlation_id,
                                  payload: { from_stage: from_stage, message_id: message.id, escalation_reason: escalation_reason })

    if escalation_reason
      ScanSolo::Commercial::EscalationService.call(opportunity: opportunity, reason: escalation_reason, turn: turn)
    else
      ActiveRecord.after_all_transactions_commit { notify }
    end
  end

  private

  attr_reader :opportunity, :turn, :message, :escalation_reason

  def notify
    payload = ScanSolo::Notifications::NegotiationPayload.build(opportunity: opportunity.reload, trigger_message: message,
                                                                correlation_id: turn.correlation_id)
    ScanSolo::Notifications::Publisher.call(event: EVENT, payload: payload)
  end
end
