# Sole entry point for a canonical guarded AI turn, called by
# ScanSolo::AiTurnJob (which holds the per-conversation Redis mutex, RF-11)
# once the triggering message is already persisted natively. Sequences:
# turn lookup/creation (RF-09) -> eligibility (RF-10) -> attachment/link
# reading (lead state RF-17..RF-20) -> context and retrieval (RF-05, RF-46)
# -> input guardrail -> up to 2 attempts -> reply-completeness cadence rule
# (RF-28).
#
# Turn states are always terminal at the end of a run (RF-07): a terminal
# turn is never reprocessed and a `pending` turn without a response resumes
# on the same row and correlation id (RF-09); any exception after the turn
# row exists marks it `failed` with the exception class and redacted message
# and reports it with the correlation id.
#
# Attempts (lead state RF-05, RF-11a): each one makes a single model call,
# outside any lock or transaction, then takes the ScanSolo::ConversationExtension
# row lock and rechecks eligibility (flag, allowlist, no active bot,
# published+enabled config), `ai_active`, no human reply after the trigger,
# the trigger still being the latest incoming message, and the turn still
# `pending` (the stale sweeper may have failed it). Only then
# ScanSolo::AiTurn::AttemptRunner writes the extractions, runs the actions,
# validates the reply against the updated lead state and sends it, rolling
# the attempt back when the validator blocks. The same eligibility checks run
# once before the first model call so a turn that could never be sent costs
# no model invocation.
#
# A 1st-attempt violation in OutputValidator::REGENERABLE_VIOLATIONS is kept
# in `context_snapshot['output_regeneration']` and the model is called once
# more with it; a 2nd rejection, or any other violation, fails the turn with
# 0 messages. An action exception rolls every change of the turn back and
# fails it (all-or-nothing). The attachment extraction evidence (RF-20) is
# in `context_snapshot['attachment_extraction']` whatever the outcome.
class ScanSolo::AiTurn::TurnOrchestrator
  ELIGIBILITY_REASONS = %w[inbox_has_active_bot config_unavailable].freeze
  MAX_ATTEMPTS = 2

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
    attachment_reading = ScanSolo::AiTurn::AttachmentReader.call(message: message)
    context = assemble_context!(turn, config, attachment_reading)

    guardrail_outcome = ScanSolo::AiTurn::InputGuardrail.call(config: config, content: message.content)
    turn.update!(guardrail_outcome: guardrail_outcome)
    return suppress!(turn, 'input guardrail blocked: forbidden subject') if guardrail_outcome[:blocked]

    run_attempts(turn, config, context, guardrail_outcome[:allowed_actions], attachment_reading.updates)
  rescue StandardError => e
    record_exception!(turn, e)
  end

  def assemble_context!(turn, config, attachment_reading)
    context = ScanSolo::AiTurn::ContextAssembler.call(message: message, config: config, attachment_reading: attachment_reading)
    evidence = context[:knowledge_context][:chunks].map { |chunk| chunk.slice(:source_id, :source_title, :chunk_id, :similarity_score) }
    turn.update!(context_snapshot: context.merge(attachment_extraction: attachment_reading.evidence), knowledge_evidence: evidence)
    context
  end

  def run_attempts(turn, config, context, offered_actions, pending_updates)
    previous_violation = nil

    MAX_ATTEMPTS.times do |attempt|
      payload = ScanSolo::AiTurn::PromptBuilder.call(config: config, context: context, offered_actions: offered_actions,
                                                     previous_violation: previous_violation)
      result = ScanSolo::AiTurn::ModelInvoker.call(config: config, payload: payload, llm_provider: llm_provider)
      return fail!(turn, result.failure_reason) if result.failed?

      outcome = send_response(turn, config, result, pending_updates)
      break unless outcome&.status == :blocked

      previous_violation = outcome.violation.to_s
      regenerable = attempt.zero? && ScanSolo::AiTurn::OutputValidator::REGENERABLE_VIOLATIONS.include?(outcome.violation)
      return fail!(turn, "output validation blocked: #{previous_violation}") unless regenerable

      turn.update!(context_snapshot: turn.context_snapshot.merge('output_regeneration' => { 'first_attempt_violation' => previous_violation }))
    end
  end

  # Returns the AttemptRunner result, or nil when the turn is no longer
  # pending or the recheck suppressed it.
  def send_response(turn, config, result, pending_updates)
    reason = nil
    outcome = nil
    extension = ScanSolo::ConversationExtension.resolve_for(conversation)

    extension.with_lock do
      turn.lock!
      next unless turn.pending?

      reason = ineligibility_reason(extension)
      next if reason

      outcome = ScanSolo::AiTurn::AttemptRunner.call(turn: turn, message: message, config: config, result: result, opportunity: opportunity,
                                                     pending_updates: pending_updates)
    end

    suppress!(turn, reason) if reason
    outcome
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

  def opportunity
    @opportunity ||= ScanSolo::PipelineOpportunity.find_by(conversation_id: conversation.id)
  end
end
