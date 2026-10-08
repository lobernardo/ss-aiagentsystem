# RF-16 / RF-18 / RNF-06: an incoming e-mail in the lead's proposal thread
# (`proposal.email_conversation`, marker `proposal_delivery`). Only a reply
# whose sender is the opportunity contact's e-mail (case-insensitive, Q-04)
# counts: under the opportunity row lock, and once per message (keyed by the
# `proposal.lead_email_reply` audit), it records the customer interaction at
# the message time, interrupts the cadence (every `scheduled` attempt in
# `proposta_enviada`) and records 1 audit with the quote request's correlation
# id. Any other sender (e.g. the commercial CC replying to all) has no effect.
# Never a `QuoteReply`, an opportunity, a CT-04 read nor an AI turn.
class ScanSolo::Proposal::LeadEmailReplyService
  EVENT_TYPE = 'proposal.lead_email_reply'.freeze

  def self.call(message:)
    proposal = ScanSolo::Proposal.find_by!(email_conversation_id: message.conversation_id)
    opportunity = proposal.opportunity
    sender_email = message.sender&.email
    return unless sender_email.present? && sender_email.casecmp?(opportunity.contact.email.to_s)

    opportunity.with_lock do
      next if ScanSolo::AuditEvent.where(event_type: EVENT_TYPE).exists?(["payload ->> 'message_id' = ?", message.id.to_s])

      opportunity.record_customer_interaction!(at: message.created_at)
      ScanSolo::Cadence::ReplyInterruptionService.call(opportunity: opportunity, message: message)
      ScanSolo::AuditLogger.record!(
        subject: opportunity, event_type: EVENT_TYPE, correlation_id: opportunity.quote_request.correlation_id,
        payload: { proposal_id: proposal.id, message_id: message.id }
      )
    end
  end
end
