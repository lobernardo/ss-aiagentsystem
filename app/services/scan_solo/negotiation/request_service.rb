# RF-35..RF-39: the only automatic path to `negociacao`. Runs inside the AI
# attempt's transaction (rolled back with it when the validator blocks):
# 1. from `proposta_enviada`, moves to `negociacao` through
#    ScanSolo::Pipeline::StageTransitionService with system authorization;
#    already in `negociacao`, no stage event (RF-35);
# 2. requests the handoff (private note + awaiting_human) and pauses the
#    cadence with the `handoff` trigger, the same pair as HandoffAction;
# 3. records `negotiation.requested` with the turn's correlation id.
# After the commit, the CT-07 notification goes through the replaceable
# ScanSolo::Notifications::Publisher (RF-37, RF-41) and, when the published
# commercial user is an agent of the conversation's inbox, the conversation
# is assigned to them natively (RF-38). Neither failure undoes the
# negotiation: both become an AuditEvent and a tracked exception (RF-39).
class ScanSolo::Negotiation::RequestService
  EVENT = 'negotiation.requested'.freeze
  HANDOFF_REASON = 'Pedido de negociação comercial'.freeze

  def self.call(opportunity:, turn:, message:)
    new(opportunity: opportunity, turn: turn, message: message).call
  end

  def initialize(opportunity:, turn:, message:)
    @opportunity = opportunity
    @turn = turn
    @message = message
  end

  def call
    from_stage = opportunity.stage
    if opportunity.proposta_enviada?
      ScanSolo::Pipeline::StageTransitionService.new(opportunity: opportunity, target_stage: 'negociacao', authorized: true).call
    end

    ScanSolo::Handoff::HandoffService.call(conversation: conversation, reason: HANDOFF_REASON)
    ScanSolo::Cadence::StopRecalculatePolicy.call(opportunity: opportunity, trigger: 'handoff')

    ScanSolo::AuditLogger.record!(subject: opportunity, event_type: EVENT, correlation_id: turn.correlation_id,
                                  payload: { from_stage: from_stage, message_id: message.id })

    ActiveRecord.after_all_transactions_commit { notify_and_assign }
  end

  private

  attr_reader :opportunity, :turn, :message

  def conversation
    opportunity.conversation
  end

  def notify_and_assign
    payload = ScanSolo::Notifications::NegotiationPayload.build(opportunity: opportunity.reload, trigger_message: message,
                                                                correlation_id: turn.correlation_id)
    ScanSolo::Notifications::Publisher.call(event: EVENT, payload: payload)
    assign_commercial_user
  end

  def assign_commercial_user
    user_id = ScanSolo::AiAgentConfig.published_for(opportunity.account).commercial_user_id
    return if user_id.blank? || !conversation.inbox.inbox_members.exists?(user_id: user_id)

    conversation.update!(assignee_id: user_id)
  rescue StandardError => e
    ScanSolo::AuditLogger.record!(subject: opportunity, event_type: 'negotiation.assignment_failed', correlation_id: turn.correlation_id,
                                  payload: { user_id: user_id, reason: e.message })
    ChatwootExceptionTracker.new(e, account: opportunity.account).capture_exception
  end
end
