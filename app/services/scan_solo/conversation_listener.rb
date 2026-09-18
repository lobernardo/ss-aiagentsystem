# Initial subscription to the native Dispatcher/AsyncDispatcher seam
# (RF-96); superseded by the canonical AI-turn listener in a later phase.
# Keeps ScanSolo::PipelineOpportunity#last_customer_interaction_at fresh for
# every real inbound message (feeds RF-11/RF-12) and applies the Novo Lead ->
# Em Contato deterministic rule (RF-14).
class ScanSolo::ConversationListener < BaseListener
  def message_created(event)
    message = event.data[:message]
    return unless message.incoming?

    opportunity = ScanSolo::PipelineOpportunity.find_by(conversation_id: message.conversation_id)
    return if opportunity.blank?

    opportunity.record_customer_interaction!(at: message.created_at)

    ScanSolo::Pipeline::InboundMessageTransitionRule.call(message: message)
  end
end
