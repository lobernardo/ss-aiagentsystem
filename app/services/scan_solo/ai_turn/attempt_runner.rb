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
#    then the commercial requests (escalação comercial RF-13/RF-14/RF-19 +
#    escalação filtrada RF-13): a negotiation (`lead_state_update` with
#    `negotiation_requested` or `escalate_to_commercial` with reason
#    `negociacao`, the reason read from the model's params since a refused
#    action result carries none), or a proposal doubt (`escalate_to_commercial`
#    with `duvida_proposta`) in `qualificado`, on an opportunity in
#    EscalationGate::QUALIFIED_STAGES runs ScanSolo::Negotiation::RequestService
#    (stage move regardless of the gate). With a published number a
#    negotiation always goes through ScanSolo::Commercial::EscalationService
#    (eligibility gate, 1 decision per turn); without one, the standard
#    negotiation reply when RequestService ran;
# 4. the turn's commercial decision, read from its `correlation_id` audits,
#    picks the reply (escalação filtrada RF-01..RF-05, RF-08): approved -> the
#    escalation reply (link placeholder + published `quote_recipient_email`);
#    `etapa_nao_qualificada` -> the model reply when it carries the published
#    e-mail and asks the eligible field(s), else the fixed e-mail-first text
#    asking them (`quote_pending` when this attempt just concluded the
#    qualification); `orcamento_nao_enviado` -> `quote_pending` (over the
#    completion reply); `primeiro_pedido_email` -> `quote_sent`. Then the
#    commercial link (ScanSolo::Commercial::WhatsappLink, published number
#    only) replaces the first placeholder only when this attempt escalated;
#    every other placeholder is dropped (RF-06, RF-07);
# 5. ScanSolo::AiTurn::OutputValidator checks the reply against the reloaded
#    lead state projection and the model's `asked_fields` (RF-11, RF-12,
#    RF-22), the commercial link (always given with a published number), the
#    approved escalation (RF-09) and the allowed phones (RF-07). A blocked
#    reply rolls the savepoint back -- 0 changes of the attempt persist, the
#    escalation mark included -- and returns the violation. The attempt whose
#    actions recorded `em_bloco` for this message is the bulk start, so every
#    relevant pending field must be asked (proposta-template-local RF-38 c);
# 6. an approved reply is sent through ScanSolo::AiTurn::ResponseSender.
# An exception propagates, so the caller rolls the whole turn back.
#
# The fallback attempt (`fallback: true`), run by the orchestrator once the
# model's replies were blocked, keeps the model's actions and replaces its
# reply with a fixed one built from the updated lead state, so the customer
# always gets an answer: the completion reply when the attempt concludes, a
# notice that new data goes with the request once concluded, the next
# eligible field(s) of a budget intent (every relevant pending key in
# `em_bloco`), else a generic question.
class ScanSolo::AiTurn::AttemptRunner # rubocop:disable Metrics/ClassLength
  Result = Struct.new(:status, :violation, keyword_init: true)

  TURN_SCOPED_PARAMS = ScanSolo::AiTurn::PromptBuilder::TURN_SCOPED_PARAMS
  QUALIFIED_STAGES = ScanSolo::Commercial::EscalationGate::QUALIFIED_STAGES
  PLACEHOLDER = ScanSolo::Commercial::WhatsappLink::PLACEHOLDER
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
      build_reply!(evidence)

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

  attr_reader :turn, :message, :config, :result, :opportunity, :pending_updates, :fallback, :commercial_link

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

  def build_reply!(evidence)
    concluded = opportunity.present? && ScanSolo::LeadState::CompletionService.call(opportunity: opportunity, turn: turn)
    if concluded
      reply_completion!
    elsif fallback
      reply_fallback!
    end
    if opportunity
      handle_commercial_request!(evidence)
      apply_commercial_outcome!(concluded)
    end
    resolve_commercial_link!
  end

  def handle_commercial_request!(evidence)
    stage = opportunity.reload.stage
    reason = commercial_request_reason(evidence, stage)
    return unless reason

    number_published = config.commercial_whatsapp_number.present?
    requested = QUALIFIED_STAGES.include?(stage)
    if requested
      ScanSolo::Negotiation::RequestService.call(opportunity: opportunity, turn: turn, message: message,
                                                 escalation_reason: number_published ? reason : nil)
    end

    if number_published
      escalate_negotiation! if reason == 'negociacao'
    elsif requested
      replace_reply!(I18n.t('scan_solo.negotiation.standard_reply'))
    end
  end

  # Goes through the gate even outside QUALIFIED_STAGES, so a negotiation
  # signalled only by `lead_state_update` records the turn's refusal; the
  # escalation reply follows only an approved decision (apply_commercial_outcome!).
  def escalate_negotiation!
    ScanSolo::Commercial::EscalationService.call(opportunity: opportunity, reason: 'negociacao', turn: turn)
  end

  def commercial_request_reason(evidence, stage)
    reasons = model_escalation_reasons
    negotiation = reasons.include?('negociacao') ||
                  evidence.any? { |item| item in { action_id: 'lead_state_update', result: { negotiation_requested: true } } }
    return 'negociacao' if negotiation

    'duvida_proposta' if reasons.include?('duvida_proposta') && stage == 'qualificado'
  end

  # Read from the model's params: a refused action result carries no reason (CT-01).
  def model_escalation_reasons
    result.actions.filter_map do |action|
      action['params'].to_h.stringify_keys['reason'] if action['action_id'].to_s == 'escalate_to_commercial'
    end
  end

  def apply_commercial_outcome!(concluded)
    decision = turn_commercial_decision
    email = config.quote_recipient_email

    case decision
    when 'approved'
      replace_reply!(I18n.t('scan_solo.negotiation.escalation_reply', link: PLACEHOLDER, email: email))
    when 'etapa_nao_qualificada'
      concluded ? replace_reply!(I18n.t('scan_solo.commercial.email_first.quote_pending', email: email)) : reply_before_qualified!(email)
    when 'orcamento_nao_enviado'
      replace_reply!(I18n.t('scan_solo.commercial.email_first.quote_pending', email: email))
    when 'primeiro_pedido_email'
      replace_reply!(I18n.t('scan_solo.commercial.email_first.quote_sent', email: email))
    end
  end

  # 'approved', a CT-01 refusal symbol or nil (no commercial request this turn).
  def turn_commercial_decision
    events = ScanSolo::AuditEvent.where(subject: opportunity, correlation_id: turn.correlation_id,
                                        event_type: [ScanSolo::Commercial::EscalationService::EVENT,
                                                     ScanSolo::Commercial::EscalationService::REFUSED_EVENT]).to_a
    return 'approved' if events.any? { |event| event.event_type == ScanSolo::Commercial::EscalationService::EVENT }

    events.first&.payload&.dig('refusal')
  end

  def escalated_in_attempt?
    opportunity.present? && turn_commercial_decision == 'approved'
  end

  # RF-01/RF-02: the model reply stays when it already carries the published
  # e-mail and, with an eligible field, asks something; otherwise the fixed
  # e-mail-first text asks the next eligible field(s).
  def reply_before_qualified!(email)
    keys = email_first_keys(ScanSolo::LeadState::Projection.call(opportunity: opportunity.reload, config: config))
    return if !fallback && result.content.to_s.include?(email) && (keys.empty? || result.asked_fields.present?)

    content = if keys.any?
                I18n.t('scan_solo.commercial.email_first.before_qualified_ask', email: email, fields: field_labels(keys))
              else
                I18n.t('scan_solo.commercial.email_first.before_qualified', email: email)
              end
    @result = result.dup.tap do |reply|
      reply.content = content
      reply.asked_fields = keys
    end
  end

  def replace_reply!(content)
    @result = result.dup.tap do |reply|
      reply.content = content
      reply.asked_fields = []
    end
  end

  # RF-06/RF-07: the link only goes in when this attempt escalated.
  def resolve_commercial_link!
    @commercial_link = ScanSolo::Commercial::WhatsappLink.build(config: config, opportunity: opportunity) if opportunity
    content = result.content.to_s
    content = if commercial_link && escalated_in_attempt?
                content.sub(PLACEHOLDER) { commercial_link }.gsub(PLACEHOLDER, '')
              else
                content.gsub(PLACEHOLDER, '')
              end
    @result = result.dup.tap { |reply| reply.content = content }
  end

  def reply_completion!
    replace_reply!(I18n.t('scan_solo.qualification.completed_reply'))
  end

  def reply_fallback!
    lead_state = ScanSolo::LeadState::Projection.call(opportunity: opportunity.reload, config: config) if opportunity
    keys = fallback_keys(lead_state)
    content = if lead_state&.qualification&.fetch(:status) == 'concluida'
                I18n.t('scan_solo.qualification.fallback_reply.concluded')
              elsif keys.any?
                I18n.t('scan_solo.qualification.fallback_reply.ask', fields: field_labels(keys))
              else
                I18n.t('scan_solo.qualification.fallback_reply.generic')
              end

    @result = result.dup.tap do |reply|
      reply.content = content
      reply.asked_fields = keys
    end
  end

  def fallback_keys(lead_state)
    return [] unless ScanSolo::AiTurn::ContextAssembler::BUDGET_INTENTS.include?(lead_state&.intent)

    email_first_keys(lead_state)
  end

  def email_first_keys(lead_state)
    return [] unless lead_state&.qualification&.fetch(:status) == 'em_andamento'
    return lead_state.relevant_pending_keys if lead_state.collection[:mode] == 'em_bloco'

    lead_state.eligible_keys.first(1)
  end

  def field_labels(keys)
    keys.map { |key| LEAD_STATE_LABELS.fetch(key) }.join(', ')
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
                                           bulk_started: lead_state.present? && lead_state.collection[:mode_source_message_id] == message.id,
                                           commercial_link: commercial_link, escalation_approved: escalated_in_attempt?,
                                           allowed_phone_numbers: allowed_phone_numbers)
  end

  def allowed_phone_numbers
    [config.commercial_whatsapp_number, message.conversation.contact.phone_number,
     opportunity&.lead_state&.fields.to_h.dig('telefone', 'value')].compact_blank
  end
end
