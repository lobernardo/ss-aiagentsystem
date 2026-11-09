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
#    every required field is now `confirmado` (RF-21); the model wrote its
#    reply before knowing its fields conclude it and may still ask something
#    (blocked as `qualification_closed`, the turn ending with 0 messages), so
#    the concluding attempt replaces it with the standard completion reply --
#    an intent, never "sent": the quote e-mail only goes after the commit;
#    a `lead_state_update` evidence with `negotiation_requested` on an
#    opportunity in `proposta_enviada`/`negociacao` runs
#    ScanSolo::Negotiation::RequestService and replaces the model's reply
#    with the standard negotiation reply (RF-35); earlier stages ignore it;
# 4. ScanSolo::AiTurn::OutputValidator checks the reply against the reloaded
#    lead state projection and the model's `asked_fields` (RF-11, RF-12,
#    RF-22). A blocked reply rolls the savepoint back -- 0 changes of the
#    attempt persist -- and returns the violation. The attempt whose actions
#    recorded `em_bloco` for this message is the bulk start, so every relevant
#    pending field must be asked (proposta-template-local RF-38 c);
# 5. an approved reply is sent through ScanSolo::AiTurn::ResponseSender.
# An exception propagates, so the caller rolls the whole turn back.
#
# The fallback attempt (`fallback: true`), run by the orchestrator once the
# model's replies were blocked, keeps the model's actions and replaces its
# reply with a fixed one built from the updated lead state, so the customer
# always gets an answer: the completion reply when the attempt concludes, a
# notice that new data goes with the request once concluded, the next
# eligible field(s) of a budget intent (every relevant pending key in
# `em_bloco`), else a generic question.
class ScanSolo::AiTurn::AttemptRunner
  Result = Struct.new(:status, :violation, keyword_init: true)

  TURN_SCOPED_PARAMS = ScanSolo::AiTurn::PromptBuilder::TURN_SCOPED_PARAMS
  NEGOTIATION_STAGES = %w[proposta_enviada negociacao].freeze
  LEAD_STATE_LABELS = ScanSolo::AiTurn::LeadStatePrompt::CATALOG_LABELS

  # rubocop:disable Metrics/ParameterLists
  def self.call(turn:, message:, config:, result:, opportunity:, pending_updates:, fallback: false)
    new(turn: turn, message: message, config: config, result: result, opportunity: opportunity, pending_updates: pending_updates,
        fallback: fallback).call
  end

  def initialize(turn:, message:, config:, result:, opportunity:, pending_updates:, fallback: false)
    @turn = turn
    @message = message
    @config = config
    @result = result
    @opportunity = opportunity
    @pending_updates = pending_updates
    @fallback = fallback
  end
  # rubocop:enable Metrics/ParameterLists

  def call
    outcome = nil

    ActiveRecord::Base.transaction(requires_new: true) do
      apply_pending_updates! if opportunity
      evidence = execute_actions
      if opportunity && ScanSolo::LeadState::CompletionService.call(opportunity: opportunity, turn: turn)
        reply_completion!
      elsif fallback
        reply_fallback!
      end
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

  attr_reader :turn, :message, :config, :result, :opportunity, :pending_updates, :fallback

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
    ScanSolo::Negotiation::RequestService.call(opportunity: opportunity, turn: turn, message: message, escalation_reason: nil)
    @result = result.dup.tap do |reply|
      reply.content = I18n.t('scan_solo.negotiation.standard_reply')
      reply.asked_fields = []
    end
  end

  def reply_completion!
    @result = result.dup.tap do |reply|
      reply.content = I18n.t('scan_solo.qualification.completed_reply')
      reply.asked_fields = []
    end
  end

  def reply_fallback!
    lead_state = ScanSolo::LeadState::Projection.call(opportunity: opportunity.reload, config: config) if opportunity
    keys = fallback_keys(lead_state)
    content = if lead_state&.qualification&.fetch(:status) == 'concluida'
                I18n.t('scan_solo.qualification.fallback_reply.concluded')
              elsif keys.any?
                I18n.t('scan_solo.qualification.fallback_reply.ask', fields: keys.map { |key| LEAD_STATE_LABELS.fetch(key) }.join(', '))
              else
                I18n.t('scan_solo.qualification.fallback_reply.generic')
              end

    @result = result.dup.tap do |reply|
      reply.content = content
      reply.asked_fields = keys
    end
  end

  def fallback_keys(lead_state)
    return [] unless lead_state&.qualification&.fetch(:status) == 'em_andamento'
    return [] unless ScanSolo::AiTurn::ContextAssembler::BUDGET_INTENTS.include?(lead_state.intent)
    return lead_state.relevant_pending_keys if lead_state.collection[:mode] == 'em_bloco'

    lead_state.eligible_keys.first(1)
  end

  def action_params(action_id, params)
    scoped_ids = { 'conversation_id' => message.conversation_id, 'opportunity_id' => opportunity&.id }
    declared = ScanSolo::Actions::Registry.handler_for(action_id)::SCHEMA['properties'].keys

    params.to_h.stringify_keys.except(*TURN_SCOPED_PARAMS).merge(scoped_ids.slice(*declared))
  end

  def validate_reply
    lead_state = ScanSolo::LeadState::Projection.call(opportunity: opportunity.reload, config: config) if opportunity
    ScanSolo::AiTurn::OutputValidator.call(content: result.content, restricted_information: config.restricted_information,
                                           asked_fields: result.asked_fields, lead_state: lead_state,
                                           bulk_started: lead_state.present? && lead_state.collection[:mode_source_message_id] == message.id)
  end
end
