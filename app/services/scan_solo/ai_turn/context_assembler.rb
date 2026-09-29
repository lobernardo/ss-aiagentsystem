# Assembles turn context from, at minimum, five sources (RF-39): recent
# canonical Chatwoot conversation history, contact context, pipeline/
# opportunity context, proposal context, and RAG retrieval results. Every
# key is always present in the returned snapshot — either populated or an
# explicit `{ available: false, reason: 'not_applicable' }` marker — so a
# caller/test can assert all five sources were considered without treating a
# missing key as an oversight.
#
# The opportunity context carries the collected and missing required
# qualification fields of the published config (RF-05), as reported by
# ScanSolo::Qualification::FieldResolver -- a field is satisfied only when
# `confirmado` in the lead state (RF-08) -- and the knowledge
# context carries exactly the chunks that go into the prompt, with the
# `{source_id, source_title, chunk_id, similarity_score}` evidence the turn
# persists (RF-46); a retrieval outage yields no chunks plus its reason.
#
# Durable semantic memory (RF-40) is a sixth, auxiliary key: it is included
# only when a memory_provider is injected, and its absence never removes
# conversation_history, which always comes straight from native `Message`
# records.
#
# Lead state (RF-09, RF-16, RF-17, RF-20, RF-25): `lead_state_context` is the
# ScanSolo::LeadState::Projection of the opportunity with the current
# message's attachment/link extractions overlaid as pending `inferido`
# values, plus `summary_allowed` -- true only when a stage change, the
# qualification completion or a next action was recorded after the last AI
# reply -- and the per-attachment extraction evidence. Every history entry
# describes its attachments (type, file name, coordinates, link, whether
# something was extracted) and URLs, so an attachment-only message is never
# an empty turn to the model.
class ScanSolo::AiTurn::ContextAssembler
  RECENT_MESSAGE_LIMIT = 20

  NOT_APPLICABLE = { available: false, reason: 'not_applicable' }.freeze

  def self.call(message:, config:, attachment_reading:, retrieval_service: ScanSolo::Knowledge::RetrievalService, memory_provider: nil)
    new(message: message, config: config, attachment_reading: attachment_reading, retrieval_service: retrieval_service,
        memory_provider: memory_provider).call
  end

  def initialize(message:, config:, attachment_reading:, retrieval_service: ScanSolo::Knowledge::RetrievalService, memory_provider: nil)
    @message = message
    @config = config
    @attachment_reading = attachment_reading
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
      lead_state_context: lead_state_context,
      proposal_context: proposal_context,
      knowledge_context: knowledge_context,
      durable_memory: durable_memory
    }
  end

  private

  attr_reader :message, :config, :attachment_reading, :conversation, :account, :retrieval_service, :memory_provider

  def opportunity
    return @opportunity if defined?(@opportunity)

    @opportunity = ScanSolo::PipelineOpportunity.includes(:contact, lead_state: :events).find_by(conversation_id: conversation.id)
  end

  def conversation_history
    conversation.messages.chat.includes(attachments: { file_attachment: :blob })
                .reorder(created_at: :desc).limit(RECENT_MESSAGE_LIMIT).reload.reverse.map do |m|
      {
        role: m.incoming? ? 'customer' : 'agent', content: m.content, created_at: m.created_at,
        attachments: m.attachments.sort_by(&:id).map { |attachment| describe_attachment(m, attachment) },
        urls: ScanSolo::AiTurn::AttachmentReader.urls(m.content)
      }
    end
  end

  def describe_attachment(history_message, attachment)
    location = attachment.location?
    {
      id: attachment.id,
      type: ScanSolo::AiTurn::AttachmentReader.pdf?(attachment) ? 'pdf' : attachment.file_type,
      file_name: (attachment.file.filename.to_s if attachment.file.attached?),
      lat: (attachment.coordinates_lat if location),
      long: (attachment.coordinates_long if location),
      link: location ? ScanSolo::AiTurn::AttachmentReader.location_link(attachment) : attachment.external_url,
      extracted: extracted?(history_message, attachment)
    }
  end

  # The current message's flag comes from this turn's reading; an earlier
  # attachment counts as extracted when the lead state records it as origin.
  def extracted?(history_message, attachment)
    if history_message.id == message.id
      attachment_reading.evidence.any? { |entry| entry[:attachment_id] == attachment.id && entry[:extracted] }
    else
      extracted_attachment_ids.include?(attachment.id)
    end
  end

  def extracted_attachment_ids
    @extracted_attachment_ids ||= if opportunity.blank?
                                    Set.new
                                  else
                                    (projection.blocks.values.flatten + projection.history).pluck(:source_attachment_id).compact.to_set
                                  end
  end

  def projection
    @projection ||= ScanSolo::LeadState::Projection.call(
      opportunity: opportunity, config: config,
      pending_updates: attachment_reading.updates.map { |update| update.merge(source_message_id: message.id) }
    )
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
    return NOT_APPLICABLE if opportunity.blank?

    resolver = ScanSolo::Qualification::FieldResolver.call(opportunity: opportunity, config: config)

    {
      available: true,
      stage: opportunity.stage,
      owner_id: opportunity.owner_id,
      last_customer_interaction_at: opportunity.last_customer_interaction_at,
      collected_fields: resolver.collected,
      missing_fields: resolver.missing_labels
    }
  end

  def lead_state_context
    return NOT_APPLICABLE if opportunity.blank?

    projection.to_h.merge(summary_allowed: summary_allowed?, attachment_extraction: attachment_reading.evidence)
  end

  # RF-25 (Q4): a stage change, the qualification completion or a next action
  # recorded since the last AI reply allows a full data summary.
  def summary_allowed?
    last_ai_reply_at = conversation.messages.outgoing.where("messages.additional_attributes ->> 'scansolo_origin' = 'ai'").maximum(:created_at)
    event_times = [opportunity.stage_events.maximum(:created_at), projection.qualification[:completed_at], projection.next_action&.dig(:recorded_at)]
    event_times.compact.any? { |at| last_ai_reply_at.nil? || at > last_ai_reply_at }
  end

  # No ScanSolo proposal module exists yet (planned for a later phase) — every
  # turn's context snapshot carries the explicit not-applicable marker until
  # it does, rather than a silently absent key.
  def proposal_context
    NOT_APPLICABLE
  end

  # An attachment-only message has no text to search with, so it retrieves
  # nothing instead of embedding an empty query.
  def knowledge_context
    return { chunks: [], failure_reason: nil } if message.content.blank?

    retrieval = retrieval_service.call(account: account, query: message.content)
    chunks = retrieval[:results].map do |result|
      {
        source_id: result.source_id, source_title: result.source_title, chunk_id: result.chunk_id,
        similarity_score: result.similarity_score, content: result.content_snippet
      }
    end

    { chunks: chunks, failure_reason: retrieval[:failure_reason] }
  end

  def durable_memory
    return { enabled: false } if memory_provider.blank?

    { enabled: true, entries: memory_provider.call(account: account, conversation: conversation) }
  end
end
