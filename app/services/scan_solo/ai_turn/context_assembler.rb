# Assembles turn context from, at minimum, five sources (RF-39): recent
# canonical Chatwoot conversation history, contact context, pipeline/
# opportunity context, proposal context, and RAG retrieval results. Every
# key is always present in the returned snapshot — either populated or an
# explicit `{ available: false, reason: 'not_applicable' }` marker — so a
# caller/test can assert all five sources were considered without treating a
# missing key as an oversight.
#
# Durable semantic memory (RF-40) is a sixth, auxiliary key: it is included
# only when a memory_provider is injected, and its absence never removes
# conversation_history, which always comes straight from native `Message`
# records.
class ScanSolo::AiTurn::ContextAssembler
  RECENT_MESSAGE_LIMIT = 20

  NOT_APPLICABLE = { available: false, reason: 'not_applicable' }.freeze

  def self.call(message:, retrieval_service: ScanSolo::Knowledge::RetrievalService, memory_provider: nil)
    new(message: message, retrieval_service: retrieval_service, memory_provider: memory_provider).call
  end

  def initialize(message:, retrieval_service: ScanSolo::Knowledge::RetrievalService, memory_provider: nil)
    @message = message
    @conversation = message.conversation
    @account = message.account
    @retrieval_service = retrieval_service
    @memory_provider = memory_provider
  end

  def call
    {
      conversation_history: conversation_history,
      contact_context: contact_context,
      pipeline_context: pipeline_context,
      proposal_context: proposal_context,
      knowledge_context: knowledge_context,
      durable_memory: durable_memory
    }
  end

  private

  attr_reader :message, :conversation, :account, :retrieval_service, :memory_provider

  def conversation_history
    conversation.messages.chat.order(created_at: :desc).limit(RECENT_MESSAGE_LIMIT).reload.reverse.map do |m|
      { role: m.incoming? ? 'customer' : 'agent', content: m.content, created_at: m.created_at }
    end
  end

  def contact_context
    contact = conversation.contact
    return NOT_APPLICABLE if contact.blank?

    {
      available: true,
      name: contact.name,
      email: contact.email,
      phone_number: contact.phone_number,
      custom_attributes: contact.custom_attributes
    }
  end

  def pipeline_context
    opportunity = ScanSolo::PipelineOpportunity.find_by(conversation_id: conversation.id)
    return NOT_APPLICABLE if opportunity.blank?

    {
      available: true,
      stage: opportunity.stage,
      owner_id: opportunity.owner_id,
      last_customer_interaction_at: opportunity.last_customer_interaction_at
    }
  end

  # No ScanSolo proposal module exists yet (planned for a later phase) — every
  # turn's context snapshot carries the explicit not-applicable marker until
  # it does, rather than a silently absent key.
  def proposal_context
    NOT_APPLICABLE
  end

  def knowledge_context
    retrieval_service.call(account: account, query: message.content.to_s)
  end

  def durable_memory
    return { enabled: false } if memory_provider.blank?

    { enabled: true, entries: memory_provider.call(account: account, conversation: conversation) }
  end
end
