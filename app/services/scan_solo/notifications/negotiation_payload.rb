# CT-07 / RF-37: the `negotiation.requested` payload delivered unchanged to
# every notification adapter (RF-41). Read-only: the current proposal version
# (or null), its value (or null) and the last 3 chat messages, the same
# window as the handoff note (ScanSolo::Handoff::HandoffService).
class ScanSolo::Notifications::NegotiationPayload
  def self.build(opportunity:, trigger_message:, correlation_id:)
    conversation = opportunity.conversation
    version = opportunity.proposal&.current_version

    {
      account_id: opportunity.account_id,
      opportunity_id: opportunity.id,
      conversation_id: conversation.id,
      conversation_url: ScanSolo::Quote::EmailComposer.conversation_url(opportunity.account_id, conversation.display_id),
      contact: contact(opportunity),
      stage: opportunity.stage,
      request_summary: trigger_message.content,
      proposal: version && version.slice(:version_number, :proposal_number, :status).symbolize_keys.merge(document_url: version.document_url),
      current_value: version&.value && { amount: version.value.to_f, currency: version.currency },
      recent_messages: recent_messages(conversation),
      correlation_id: correlation_id
    }
  end

  def self.contact(opportunity)
    company = opportunity.lead_state&.fields.to_h['empresa'].to_h
    { name: opportunity.contact.name, company: company['status'] == 'faltante' ? nil : company['value'], phone: opportunity.contact.phone_number }
  end

  def self.recent_messages(conversation)
    conversation.messages.chat.reorder(created_at: :desc).limit(ScanSolo::Handoff::HandoffService::RECENT_MESSAGE_LIMIT).to_a.reverse.map do |message|
      { sender: message.incoming? ? 'customer' : 'agent', content: message.content, created_at: message.created_at.iso8601 }
    end
  end
  private_class_method :contact, :recent_messages
end
