# Sole entry point for a canonical guarded AI turn, called by
# ScanSolo::AiTurnJob (which holds the per-conversation Redis mutex, RF-11)
# once the triggering message is already persisted natively. Sequences:
# turn lookup/creation (RF-09) -> eligibility (RF-10) -> context and
# retrieval (RF-05, RF-46) -> input guardrail -> model invocation ->
# output validation (RF-06) -> locked pre-send recheck (RF-10) -> actions ->
# approved-response send -> reply-completeness cadence rule (RF-28).
#
# Turn states are always terminal at the end of a run (RF-07): a terminal
# turn is never reprocessed and a `pending` turn without a response resumes
# on the same row and correlation id (RF-09); any exception after the turn
# row exists marks it `failed` with the exception class and redacted message
# and reports it with the correlation id.
#
# Model-requested actions (RF-12, RF-13) run exclusively through
# ScanSolo::Actions::Registry, after the recheck and in the same transaction
# as the outgoing message, each keyed by the turn correlation id and its
# position; the conversation/opportunity ids come from the turn, never from
# the model. An action that was not offered to the model, is unregistered or
# fails schema validation raises, which rolls back every earlier action and
# fails the turn with 0 messages (all-or-nothing).
#
# The pre-send recheck runs inside the send transaction under the
# ScanSolo::ConversationExtension row lock: eligibility (flag, allowlist, no
# active bot, published+enabled config), `ai_active`, no human reply after the
# trigger, the trigger still being the latest incoming message, and the turn
# still `pending` (the stale sweeper may have failed it). The same checks run
# once before the model call so a turn that could never be sent costs no
# model invocation.
class ScanSolo::AiTurn::TurnOrchestrator
  ELIGIBILITY_REASONS = %w[inbox_has_active_bot config_unavailable].freeze

  TURN_SCOPED_PARAMS = ScanSolo::AiTurn::PromptBuilder::TURN_SCOPED_PARAMS

  def self.call(message:, llm_provider: nil)
    new(message: message, llm_provider: llm_provider).call
  end

  def initialize(message:, llm_provider: nil)
    @message = message
    @conversation = message.conversation
    @llm_provider = llm_provider
  end

  def call
    turn = resumable_turn
    return if turn.blank?

    process(turn)
    apply_reply_completeness(turn.reload)
  end

  private

  attr_reader :message, :conversation, :llm_provider

  def resumable_turn
    turn = ScanSolo::AiTurn.find_by(message_id: message.id)
    return ScanSolo::AiTurn.create!(message: message, conversation: conversation, correlation_id: SecureRandom.uuid) if turn.blank?

    turn if turn.pending? && turn.response_message_id.blank?
  end

  def process(turn)
    reason = ineligibility_reason(ScanSolo::ConversationExtension.resolve_for(conversation))
    return suppress!(turn, reason) if reason

    config = ScanSolo::AiAgentConfig.published_for(message.account)
    result = generate_validated_response(turn, config)
    send_response(turn, config, result) if result.present?
  rescue StandardError => e
    record_exception!(turn, e)
  end

  def generate_validated_response(turn, config)
    context = ScanSolo::AiTurn::ContextAssembler.call(message: message, config: config,
                                                      attachment_reading: ScanSolo::AiTurn::AttachmentReader.call(message: message))
    evidence = context[:knowledge_context][:chunks].map { |chunk| chunk.slice(:source_id, :source_title, :chunk_id, :similarity_score) }
    turn.update!(context_snapshot: context, knowledge_evidence: evidence)

    guardrail_outcome = ScanSolo::AiTurn::InputGuardrail.call(config: config, content: message.content)
    turn.update!(guardrail_outcome: guardrail_outcome)
    return suppress!(turn, 'input guardrail blocked: forbidden subject') if guardrail_outcome[:blocked]

    payload = ScanSolo::AiTurn::PromptBuilder.call(config: config, context: context, offered_actions: guardrail_outcome[:allowed_actions])
    invoke_and_validate(turn, config, payload)
  end

  def invoke_and_validate(turn, config, payload)
    result = ScanSolo::AiTurn::ModelInvoker.call(config: config, payload: payload, llm_provider: llm_provider)
    return fail!(turn, result.failure_reason) if result.failed?

    validation = ScanSolo::AiTurn::OutputValidator.call(content: result.content, restricted_information: config.restricted_information)
    return fail!(turn, "output validation blocked: #{validation[:violation]}") if validation[:blocked]

    result
  end

  def send_response(turn, config, result)
    reason = nil
    extension = ScanSolo::ConversationExtension.resolve_for(conversation)

    extension.with_lock do
      turn.lock!
      next unless turn.pending?

      reason = ineligibility_reason(extension)
      next if reason

      evidence = execute_actions(turn, result.actions)
      ScanSolo::AiTurn::ResponseSender.call(message: message, config: config, result: result, turn: turn, action_evidence: evidence)
    end

    suppress!(turn, reason) if reason
  end

  def ineligibility_reason(extension)
    eligibility = ScanSolo::Eligibility.for_message(message)
    return ELIGIBILITY_REASONS.include?(eligibility.reason) ? eligibility.reason : 'not_eligible' unless eligibility.eligible?
    return 'human_controlled' unless extension.ai_active?
    return 'human_replied' if human_replied_after_trigger?
    return 'superseded' unless conversation.messages.incoming.maximum(:id) == message.id

    nil
  end

  def human_replied_after_trigger?
    conversation.messages.outgoing
                .where(private: false, sender_type: 'User')
                .where('messages.id > ?', message.id)
                .where("COALESCE(messages.additional_attributes ->> 'scansolo_origin', '') = ''")
                .exists?
  end

  # RF-28: the customer's reply cancels/recalculates the cadence that was
  # already running when the message arrived -- the enrollment created by
  # this very message (bootstrap or stage entry) is left alone, and a burst
  # applies the rule once, through its surviving (non-superseded) turn.
  def apply_reply_completeness(turn)
    return if turn.suppressed? && turn.failure_reason == 'superseded'

    return if opportunity.blank?
    return unless opportunity.cadence_enrollments.active.exists?(['created_at < ?', message.created_at])

    ScanSolo::Cadence::ReplyCompletenessDetector.call(opportunity: opportunity)
  end

  def suppress!(turn, reason)
    turn.update!(invocation_status: :suppressed, failure_reason: reason)
    nil
  end

  def fail!(turn, reason)
    turn.update!(invocation_status: :failed, failure_reason: reason)
    nil
  end

  def record_exception!(turn, error)
    turn.reload.update!(invocation_status: :failed,
                        failure_reason: "#{error.class}: #{ScanSolo::AiTurn::PromptRedactor.call(error.message)}")
    ChatwootExceptionTracker.new(error, account: message.account, tags: { scansolo_correlation_id: turn.correlation_id }).capture_exception
  end

  def execute_actions(turn, requested_actions)
    offered = turn.guardrail_outcome['allowed_actions']

    requested_actions.each_with_index.map do |action, index|
      action_id = action['action_id'].to_s
      raise ScanSolo::Actions::Executor::UnregisteredActionError, action_id unless offered.include?(action_id)

      outcome = ScanSolo::Actions::Registry.call(
        action_id: action_id, params: action_params(action_id, action['params']), turn: turn,
        correlation_id: turn.correlation_id, idempotency_key: "#{turn.correlation_id}:#{index}:#{action_id}"
      )
      result = outcome.side_effect_result
      { action_id: action_id, index: index, execution_id: outcome.execution.id, result: result.is_a?(Hash) ? result : result.class.name }
    end
  end

  def action_params(action_id, params)
    scoped_ids = { 'conversation_id' => conversation.id, 'opportunity_id' => opportunity&.id }
    declared = ScanSolo::Actions::Registry.handler_for(action_id)::SCHEMA['properties'].keys

    params.to_h.stringify_keys.except(*TURN_SCOPED_PARAMS).merge(scoped_ids.slice(*declared))
  end

  def opportunity
    @opportunity ||= ScanSolo::PipelineOpportunity.find_by(conversation_id: conversation.id)
  end
end
