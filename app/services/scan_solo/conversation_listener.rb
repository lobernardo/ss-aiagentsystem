# Canonical subscription to the native Dispatcher/AsyncDispatcher seam
# (RF-96, CT-09). It is registered globally, so ScanSolo::Eligibility (flag +
# published inbox allowlist + no active bot, RF-01/RF-02) is classified once
# here, before any write or enqueue -- accounts and inboxes outside ScanSolo
# see zero footprint.
#
# Incoming: bootstraps the conversation's opportunity (RF-22); the creating
# message keeps it in novo_lead, later ones refresh the interaction time and
# apply the Novo Lead -> Em Contato rule (RF-23); the deterministic opt-out
# keyword check runs independently of the AI turn (RF-16 (b)); then the AI
# turn job is enqueued.
#
# Outgoing: a manual, non-private reply by a User that ScanSolo did not
# originate (no `scansolo_origin`) is an implicit takeover (RF-18).
# Assignment changes only create activity messages, so they never get here.
#
# Delivery (CT-09): a cadence/proposal template message ScanSolo created is
# reconciled on creation and on every native update (status, `source_id`)
# by ScanSolo::Messaging::DeliveryReconciler (RF-27, RF-41). This runs
# ahead of the eligibility gate -- the evidence of a message already sent
# must be recorded even if the inbox left the allowlist meanwhile -- and is
# keyed on the `scansolo_origin` marker, so other messages cost no query.
#
# The listener delegates every write to services and holds no AI logic.
class ScanSolo::ConversationListener < BaseListener
  IMPLICIT_TAKEOVER_REASON = 'Resposta humana na conversa'.freeze
  TEMPLATE_ORIGINS = %w[cadence proposal].freeze

  def message_created(event)
    message = event.data[:message]
    reconcile_delivery(message)
    return unless message.incoming? || message.outgoing?
    return unless ScanSolo::Eligibility.for_message(message).eligible?

    message.incoming? ? handle_incoming(message) : handle_outgoing(message)
  end

  def message_updated(event)
    reconcile_delivery(event.data[:message])
  end

  private

  def reconcile_delivery(message)
    return unless message.outgoing? && TEMPLATE_ORIGINS.include?(message.additional_attributes.to_h['scansolo_origin'])

    ScanSolo::Messaging::DeliveryReconciler.call(message: message)
  end

  def handle_incoming(message)
    bootstrap = ScanSolo::Pipeline::OpportunityBootstrapService.call(message: message)
    unless bootstrap.created?
      bootstrap.opportunity.record_customer_interaction!(at: message.created_at)
      ScanSolo::Pipeline::InboundMessageTransitionRule.call(message: message)
    end

    keywords = ScanSolo::AiAgentConfig.published_for(message.account).opt_out_keywords
    if ScanSolo::OptOut::KeywordMatcher.match?(message.content, keywords)
      ScanSolo::OptOut::MarkService.call(contact: message.conversation.contact, source: 'keyword')
    end

    ScanSolo::AiTurnJob.perform_later(message.id)
  end

  def handle_outgoing(message)
    return if message.private?
    return unless message.sender.is_a?(User)
    return if message.additional_attributes.to_h['scansolo_origin'].present?

    ScanSolo::Handoff::TakeoverService.call(
      conversation: message.conversation, reason: IMPLICIT_TAKEOVER_REASON, actor: message.sender, trigger: 'human_reply'
    )
  end
end
