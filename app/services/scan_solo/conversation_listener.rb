# Canonical subscription to the native Dispatcher/AsyncDispatcher seam
# (RF-96, RF-35): every real inbound message on a ScanSolo-enabled account
# both keeps ScanSolo::PipelineOpportunity#last_customer_interaction_at fresh
# (RF-11/RF-12), applies the Novo Lead -> Em Contato deterministic rule
# (RF-14), and enqueues the guarded AI turn job. Accounts without ScanSolo
# enabled see zero footprint from this listener — it is registered globally
# on AsyncDispatcher (native seam), so the enabled-account check is the
# isolation boundary (RF-95).
class ScanSolo::ConversationListener < BaseListener
  def message_created(event)
    message = event.data[:message]
    return unless message.incoming?
    return unless message.account.scansolo_enabled?

    apply_pipeline_bookkeeping(message)

    ScanSolo::AiTurnJob.perform_later(message.id)
  end

  private

  def apply_pipeline_bookkeeping(message)
    opportunity = ScanSolo::PipelineOpportunity.find_by(conversation_id: message.conversation_id)
    return if opportunity.blank?

    opportunity.record_customer_interaction!(at: message.created_at)

    ScanSolo::Pipeline::InboundMessageTransitionRule.call(message: message)
  end
end
