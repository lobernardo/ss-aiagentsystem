# Consumed exclusively from the native Dispatcher/AsyncDispatcher seam via
# ScanSolo::ConversationListener (RF-96). Only ever runs for an
# already-persisted native Message (RF-35 — the job loads it by id and is a
# no-op if it is gone); everything else (turn lifecycle, eligibility,
# context, guardrails, model invocation, action execution, send) is
# ScanSolo::AiTurn::TurnOrchestrator's responsibility.
#
# RF-11: turns of one conversation never overlap -- the job holds a
# per-conversation Redis mutex (TTL above the model timeout) around the whole
# turn, and a job that finds it taken is re-enqueued until the running turn
# has released it. A retried job resumes or no-ops on the existing turn
# (RF-09).
#
# llm_provider is forwarded to the orchestrator (RF-42): production
# enqueues (ScanSolo::ConversationListener) omit it, so a real turn invokes
# the configured provider through lib/llm; specs inject
# ScanSolo::TestMode::MockLlmProvider explicitly (RF-25). A String is
# accepted so a real Sidekiq enqueue (which serializes arguments) can carry
# an override across the queue boundary; production enqueues never set it.
class ScanSolo::AiTurnJob < MutexApplicationJob
  LOCK_KEY = 'SCANSOLO::AI_TURN::CONVERSATION::%<conversation_id>d'.freeze
  LOCK_RETRY_WAIT = 5.seconds

  queue_as :medium
  retry_on LockAcquisitionError, wait: LOCK_RETRY_WAIT, attempts: (ScanSolo::AI_TURN_LOCK_TTL / LOCK_RETRY_WAIT).ceil + 1

  def perform(message_id, llm_provider: nil)
    message = Message.find_by(id: message_id)
    return if message.blank?

    with_lock(format(LOCK_KEY, conversation_id: message.conversation_id), ScanSolo::AI_TURN_LOCK_TTL) do
      ScanSolo::AiTurn::TurnOrchestrator.call(message: message, llm_provider: resolve_provider(llm_provider))
    end
  end

  private

  def resolve_provider(llm_provider)
    return nil if llm_provider.blank?

    llm_provider.is_a?(String) ? llm_provider.constantize : llm_provider
  end
end
