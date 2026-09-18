# Consumed exclusively from the native Dispatcher/AsyncDispatcher seam via
# ScanSolo::ConversationListener (RF-96). Only ever runs for an
# already-persisted native Message (RF-35 — the job loads it by id and is a
# no-op if it is gone); everything else (dedupe, eligibility, context,
# guardrails, model invocation, action execution, send) is
# ScanSolo::AiTurn::TurnOrchestrator's responsibility.
#
# llm_provider is forwarded to the orchestrator (RF-42): production
# enqueues (ScanSolo::ConversationListener) omit it, so a real turn invokes
# the configured provider through lib/llm; specs inject
# ScanSolo::TestMode::MockLlmProvider explicitly (RF-25). A String is
# accepted so a real Sidekiq enqueue (which serializes arguments) can carry
# an override across the queue boundary; production enqueues never set it.
class ScanSolo::AiTurnJob < ApplicationJob
  queue_as :medium

  def perform(message_id, llm_provider: nil, actions: [])
    message = Message.find_by(id: message_id)
    return if message.blank?

    ScanSolo::AiTurn::TurnOrchestrator.call(
      message: message, llm_provider: resolve_provider(llm_provider), actions: actions
    )
  end

  private

  def resolve_provider(llm_provider)
    return nil if llm_provider.blank?

    llm_provider.is_a?(String) ? llm_provider.constantize : llm_provider
  end
end
