# Sole entry point for a canonical guarded AI turn (RF-35-RF-44), called by
# ScanSolo::AiTurnJob once the triggering message is already persisted
# natively. Sequences: dedupe turn creation (RF-36) -> eligibility guard
# (RF-37) -> published config lookup -> context assembly (RF-39) -> input
# guardrail (RF-38) -> model invocation (RF-42) -> output validation
# (RF-41) -> registered action execution -> approved-response send (RF-43).
#
# `actions:` is the turn's registered tool/action requests (RF-44) — a list
# of already-decided, schema-shaped action requests. The full model-driven
# action-request/authorization layer (classification, confirmation gating,
# free-form-parameter rejection) is a later phase's dedicated executor; this
# orchestrator only guarantees the transactional property RF-44 requires
# now: whatever actions are supplied execute inside the same transaction as
# the outbound response, so an action's effect (e.g. a stage transition) is
# never visible without the response being queued, and never queues the
# response without the action's effect landing first.
class ScanSolo::AiTurn::TurnOrchestrator
  SUPPORTED_ACTIONS = %w[stage_transition].freeze

  def self.call(message:, llm_provider: nil, actions: [])
    new(message: message, llm_provider: llm_provider, actions: actions).call
  end

  def initialize(message:, llm_provider: nil, actions: [])
    @message = message
    @llm_provider = llm_provider
    @actions = actions
  end

  def call
    turn = create_turn
    return if turn.blank?

    config = eligible_config(turn)
    return if config.blank?

    result = generate_validated_response(turn, config)
    return if result.blank?

    send_with_actions(turn: turn, config: config, result: result)
  end

  private

  attr_reader :message, :llm_provider, :actions

  def create_turn
    ScanSolo::AiTurn.create!(
      message: message,
      conversation: message.conversation,
      correlation_id: SecureRandom.uuid,
      invocation_status: :pending
    )
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    nil
  end

  def eligible_config(turn)
    unless ScanSolo::AiTurn::EligibilityGuard.eligible?(conversation: message.conversation)
      suppress!(turn, 'conversation is human-controlled or opted out')
      return nil
    end

    config = ScanSolo::AiAgentConfig.published_for(message.account)
    if config.blank? || !config.enabled?
      suppress!(turn, 'no published/enabled AI agent config')
      return nil
    end

    config
  end

  def generate_validated_response(turn, config)
    context = ScanSolo::AiTurn::ContextAssembler.call(message: message)
    turn.update!(context_snapshot: context)

    guardrail_outcome = ScanSolo::AiTurn::InputGuardrail.call(config: config, content: message.content)
    turn.update!(guardrail_outcome: guardrail_outcome)
    if guardrail_outcome[:blocked]
      suppress!(turn, 'input guardrail blocked: forbidden subject')
      return nil
    end

    invoke_and_validate(turn, config, context)
  end

  def invoke_and_validate(turn, config, context)
    result = ScanSolo::AiTurn::ModelInvoker.call(config: config, prompt: build_prompt(context), llm_provider: llm_provider)
    if result.failed?
      fail!(turn, result.failure_reason)
      return nil
    end

    validation = ScanSolo::AiTurn::OutputValidator.call(content: result.content)
    if validation[:blocked]
      fail!(turn, "output validation blocked: #{validation[:violation]}")
      return nil
    end

    result
  end

  def suppress!(turn, reason)
    turn.update!(invocation_status: :suppressed, failure_reason: reason)
  end

  def fail!(turn, reason)
    turn.update!(invocation_status: :failed, failure_reason: reason)
  end

  # RF-44: action execution and response persistence share one transaction —
  # if the send fails, the action rolls back with it; if an action is
  # invalid, nothing is sent.
  def send_with_actions(turn:, config:, result:)
    ActiveRecord::Base.transaction do
      evidence = execute_actions(turn.correlation_id)
      ScanSolo::AiTurn::ResponseSender.call(
        message: message, config: config, result: result, turn: turn, action_evidence: evidence
      )
    end
  end

  def execute_actions(correlation_id)
    opportunity = ScanSolo::PipelineOpportunity.find_by(conversation_id: message.conversation_id)

    actions.filter_map do |action|
      next unless SUPPORTED_ACTIONS.include?(action[:type].to_s)
      next if opportunity.blank?

      execute_stage_transition(action, opportunity, correlation_id)
    end
  end

  def execute_stage_transition(action, opportunity, correlation_id)
    params = action[:params] || {}

    ScanSolo::Pipeline::StageTransitionService.new(
      opportunity: opportunity,
      target_stage: params[:target_stage],
      actor: params[:actor],
      authorized: params[:authorized] || false
    ).call

    {
      type: 'stage_transition', target_stage: params[:target_stage], correlation_id: correlation_id,
      executed_at: Time.current
    }
  end

  def build_prompt(context)
    history = context[:conversation_history].map { |m| "#{m[:role]}: #{m[:content]}" }.join("\n")
    "Historico da conversa:\n#{history}"
  end
end
