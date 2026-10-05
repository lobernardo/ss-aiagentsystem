# CT-04 / RF-17..RF-24 / RF-42: an incoming e-mail of the quote inbox.
#
# - A reply in a negotiation notification thread is ignored (RF-42).
# - A reply in any other thread without a quote request becomes an
#   `unmatched` pending reply (RF-19), listed for a manual link (CT-08).
# - A reply to a request is read by `.apply`, also used by the manual link
#   (RF-20): under the request lock, a request already `replied` turns the
#   reply into a `late_reply` pending (RF-23, never read commercially); a
#   valid CT-04 block marks the request `replied` with its commercial data and
#   then, after commit, requests the generation (RF-24); an invalid one marks
#   it `correction_requested` and, after commit, posts the correction in the
#   request thread (RF-18). The read is deterministic, never an LLM (RF-21).
# - The accepted message itself, read again (job retry after a failed
#   generation), is not a late reply: it requests the generation again while
#   the request has no version, and is a no-op once it has one.
# - A generation error other than the proposal gate (e.g. the Make
#   integration not configured) is audited and re-raised, so the job fails
#   visibly and its retry regenerates from the kept reply.
#
# Every step records 1 audit with the request's correlation id (RF-22, RNF-09).
class ScanSolo::Quote::ReplyProcessor
  def self.call(message:)
    quote_request = ScanSolo::QuoteRequest.find_by(email_conversation_id: message.conversation_id)
    return apply(quote_request: quote_request, message: message) if quote_request
    return if message.conversation.additional_attributes.to_h['scansolo_thread'] == ScanSolo::Notifications::EmailAdapter::MARKER

    record_pending!(message: message, kind: :unmatched)
  end

  def self.apply(quote_request:, message:)
    result = ScanSolo::Quote::ResponseBlockParser.call(
      content: message.content, html: message.content_attributes.dig('email', 'html_content', 'full')
    )

    outcome = quote_request.with_lock do
      next(quote_request.reply_message_id == message.id ? :retry : :late_reply) if quote_request.replied?

      result.valid? ? accept!(quote_request, message, result) : reject!(quote_request, result)
    end

    case outcome
    when :late_reply then record_pending!(message: message, kind: :late_reply, quote_request: quote_request)
    when :accepted, :retry then request_generation!(quote_request)
    when :rejected then post_correction!(quote_request, message, result)
    end
  end

  class << self
    private

    def record_pending!(message:, kind:, quote_request: nil)
      quote_reply = ScanSolo::QuoteReply.create!(
        account: message.account, message: message, conversation_id: message.conversation_id, kind: kind, quote_request: quote_request
      )
      ScanSolo::AuditLogger.record!(
        subject: quote_request&.opportunity || quote_reply, event_type: 'quote_reply.pending',
        correlation_id: quote_request&.correlation_id || SecureRandom.uuid,
        payload: { quote_reply_id: quote_reply.id, message_id: message.id, kind: kind.to_s }
      )
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    def accept!(quote_request, message, result)
      quote_request.update!(status: :replied, commercial: result.values.as_json, reply_message_id: message.id, replied_at: Time.current)
      audit!(quote_request, 'quote_reply.accepted', message_id: message.id)
      :accepted
    end

    def reject!(quote_request, result)
      quote_request.update!(status: :correction_requested)
      audit!(quote_request, 'quote_reply.rejected', problems: result.problems.map(&:to_s))
      :rejected
    end

    def request_generation!(quote_request)
      return if ScanSolo::ProposalVersion.exists?(quote_request_id: quote_request.id)

      generate_correlation_id = SecureRandom.uuid
      version = ScanSolo::Proposal::GenerateService.call(
        opportunity: quote_request.opportunity, quote_request: quote_request, correlation_id: generate_correlation_id
      )
      audit!(quote_request, 'proposal.generation_requested', generate_correlation_id: generate_correlation_id, proposal_version_id: version.id)
    rescue ActiveRecord::RecordInvalid => e
      audit!(quote_request, 'proposal.generation_rejected', reason: e.record.errors.full_messages.to_sentence)
      ChatwootExceptionTracker.new(e, account: quote_request.account).capture_exception
    rescue StandardError => e
      audit!(quote_request, 'proposal.generation_failed', error: e.class.name, message: e.message)
      raise
    end

    def post_correction!(quote_request, message, result)
      ScanSolo::Quote::EmailThread.post!(
        conversation: quote_request.email_conversation, recipient: message.sender.email,
        email: ScanSolo::Quote::EmailComposer.correction(problems: result.problems)
      )
    end

    def audit!(quote_request, event_type, **payload)
      ScanSolo::AuditLogger.record!(
        subject: quote_request.opportunity, event_type: event_type, correlation_id: quote_request.correlation_id,
        payload: { quote_request_id: quote_request.id, **payload }
      )
    end
  end
end
