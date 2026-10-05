# CT-08: the manual decisions on a pending quote reply, serialized by the
# reply lock and audited with the actor (RNF-09).
#
# - `link!` (RF-20): only a pending `unmatched` reply links to an open request.
#   After commit the e-mail is read as that request's reply by
#   ReplyProcessor.apply, so the CT-04 rules (accept or correction) apply.
# - `discard!` (RF-23): only a pending `late_reply` is discarded; the request
#   and its version stay as they are.
class ScanSolo::Quote::PendingReplyResolution
  def self.link!(quote_reply:, quote_request:, actor:)
    ActiveRecord::Base.transaction do
      quote_reply.lock!
      quote_request.lock!
      reject!('already_linked') if quote_reply.linked?
      reject!('quote_request_closed') if quote_reply.discarded? || quote_reply.late_reply? || !quote_request.open?

      quote_reply.update!(status: :linked, quote_request: quote_request, resolved_by: actor, resolved_at: Time.current)
      ScanSolo::AuditLogger.record!(
        subject: quote_request.opportunity, event_type: 'quote_reply.linked', actor: actor, correlation_id: quote_request.correlation_id,
        payload: { quote_reply_id: quote_reply.id, quote_request_id: quote_request.id, message_id: quote_reply.message_id }
      )
    end

    ScanSolo::Quote::ReplyProcessor.apply(quote_request: quote_request, message: quote_reply.message)
    quote_request.reload
  end

  def self.discard!(quote_reply:, actor:)
    quote_reply.with_lock do
      reject!('already_discarded') if quote_reply.discarded?
      reject!('not_discardable') unless quote_reply.pending? && quote_reply.late_reply?

      quote_reply.update!(status: :discarded, resolved_by: actor, resolved_at: Time.current)
      quote_request = quote_reply.quote_request
      ScanSolo::AuditLogger.record!(
        subject: quote_request.opportunity, event_type: 'quote_reply.discarded', actor: actor, correlation_id: quote_request.correlation_id,
        payload: { quote_reply_id: quote_reply.id, quote_request_id: quote_request.id, message_id: quote_reply.message_id }
      )
    end
    quote_reply
  end

  def self.reject!(code)
    raise CustomExceptions::ScanSolo::QuoteReplyRejected, code
  end
  private_class_method :reject!
end
