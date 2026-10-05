# One attempt of a guarded AI turn (lead state RF-05, RF-11a), called by
# ScanSolo::AiTurn::TurnOrchestrator under the ConversationExtension row lock
# after the pre-send recheck. Everything runs in a savepoint, in order:
# 1. the current message's attachment/link extractions (`pending_updates`)
#    are written as `inferido` through ScanSolo::LeadState::Writer (RF-18,
#    RF-19), before any action and the reply;
# 2. the model-requested actions run exclusively through
#    ScanSolo::Actions::Registry (RF-12, RF-13), each keyed by the turn
#    correlation id and its position; the conversation/opportunity ids come
#    from the turn, never from the model. An action that was not offered to
#    the model, is unregistered or fails schema validation raises;
# 3. ScanSolo::LeadState::CompletionService concludes the qualification when
#    every required field is now `confirmado` (RF-21);
#    a `lead_state_update` evidence with `negotiation_requested` on an
#    opportunity in `proposta_enviada`/`negociacao` runs
#    ScanSolo::Negotiation::RequestService and replaces the model's reply
#    with the standard negotiation reply (RF-35); earlier stages ignore it;
# 4. ScanSolo::AiTurn::OutputValidator checks the reply against the reloaded
#    lead state projection and the model's `asked_fields` (RF-11, RF-12,
#    RF-22). A blocked reply rolls the savepoint back -- 0 changes of the
#    attempt persist -- and returns the violation;
# 5. an approved reply is sent through ScanSolo::AiTurn::ResponseSender.
# An exception propagates, so the caller rolls the whole turn back.
class ScanSolo::AiTurn::AttemptRunner
  Result = Struct.new(:status, :violation, keyword_init: true)

  TURN_SCOPED_PARAMS = ScanSolo::AiTurn::PromptBuilder::TURN_SCOPED_PARAMS
  NEGOTIATION_STAGES = %w[proposta_enviada negociacao].freeze

  # rubocop:disable Metrics/ParameterLists
  def self.call(turn:, message:, config:, result:, opportunity:, pending_updates:)
    new(turn: turn, message: message, config: config, result: result, opportunity: opportunity, pending_updates: pending_updates).call
  end

  def initialize(turn:, message:, config:, result:, opportunity:, pending_updates:)
    @turn = turn
    @message = message
    @config = config
    @result = result
    @opportunity = opportunity
    @pending_updates = pending_updates
  end
  # rubocop:enable Metrics/ParameterLists

  def call
    outcome = nil

    ActiveRecord::Base.transaction(requires_new: true) do
      apply_pending_updates! if opportunity
      evidence = execute_actions
      ScanSolo::LeadState::CompletionService.call(opportunity: opportunity, turn: turn) if opportunity
      request_negotiation! if negotiation_requested?(evidence)

      validation = validate_reply
      if validation[:blocked]
        outcome = Result.new(status: :blocked, violation: validation[:violation])
        raise ActiveRecord::Rollback
      end

      ScanSolo::AiTurn::ResponseSender.call(message: message, config: config, result: result, turn: turn, action_evidence: evidence)
      outcome = Result.new(status: :sent)
    end

    outcome
  end

  private

  attr_reader :turn, :message, :config, :result, :opportunity, :pending_updates

  def apply_pending_updates!
    writer = ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state)
    pending_updates.each do |update|
      writer.apply_field!(key: update[:key], value: update[:value], status: 'inferido', source_message_id: message.id,
                          source_attachment_id: update[:source_attachment_id])
    end
  end

  def execute_actions
    offered = turn.guardrail_outcome['allowed_actions']

    result.actions.each_with_index.map do |action, index|
      action_id = action['action_id'].to_s
      raise ScanSolo::Actions::Executor::UnregisteredActionError, action_id unless offered.include?(action_id)

      outcome = ScanSolo::Actions::Registry.call(
        action_id: action_id, params: action_params(action_id, action['params']), turn: turn,
        correlation_id: turn.correlation_id, idempotency_key: "#{turn.correlation_id}:#{index}:#{action_id}"
      )
      side_effect = outcome.side_effect_result
      { action_id: action_id, index: index, execution_id: outcome.execution.id,
        result: side_effect.is_a?(Hash) ? side_effect : side_effect.class.name }
    end
  end

  def negotiation_requested?(evidence)
    return false unless opportunity && NEGOTIATION_STAGES.include?(opportunity.reload.stage)

    evidence.any? { |item| item in { action_id: 'lead_state_update', result: { negotiation_requested: true } } }
  end

  def request_negotiation!
    ScanSolo::Negotiation::RequestService.call(opportunity: opportunity, turn: turn, message: message)
    @result = result.dup.tap do |reply|
      reply.content = I18n.t('scan_solo.negotiation.standard_reply')
      reply.asked_fields = []
    end
  end

  def action_params(action_id, params)
    scoped_ids = { 'conversation_id' => message.conversation_id, 'opportunity_id' => opportunity&.id }
    declared = ScanSolo::Actions::Registry.handler_for(action_id)::SCHEMA['properties'].keys

    params.to_h.stringify_keys.except(*TURN_SCOPED_PARAMS).merge(scoped_ids.slice(*declared))
  end

  def validate_reply
    lead_state = ScanSolo::LeadState::Projection.call(opportunity: opportunity.reload, config: config) if opportunity
    ScanSolo::AiTurn::OutputValidator.call(content: result.content, restricted_information: config.restricted_information,
                                           asked_fields: result.asked_fields, lead_state: lead_state)
  end
end
