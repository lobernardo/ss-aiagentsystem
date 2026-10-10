# RF-18 / RF-19 / CT-06 / RNF-04: the sole path of a quote e-mail delivery
# failure. Called by the QuoteRequestJob once its retries are exhausted with
# no request message (case A, `message` nil) and by the delivery reconciler
# when a created message is marked `failed` (case B).
#
# - Outside any open transaction (RNF-04), like ScanSolo::Quote::EmailThread.
# - Idempotent per failed message: a second call for a message that already
#   has its `quote_request.delivery_failed` audit does nothing.
# - One private note in the opportunity's WhatsApp conversation, with the
#   reason (exception class or native `external_error`, ≤ 200 characters) and
#   the ScanSOLO link of the quote e-mail conversation; no secret.
# - One `quote_request.delivery_failed` audit with the request's correlation
#   id and the CT-06 payload (`result` = the reason).
# The stage, the request status and the handoff state never change.
class ScanSolo::Quote::DeliveryFailureService
  EVENT = 'quote_request.delivery_failed'.freeze
  REASON_LIMIT = 200

  def self.call(opportunity:, reason:, message: nil)
    new(opportunity: opportunity, reason: reason, message: message).call
  end

  def initialize(opportunity:, reason:, message:)
    @opportunity = opportunity
    @quote_request = opportunity.quote_request
    @reason = reason.to_s.truncate(REASON_LIMIT)
    @message = message
  end

  def call
    raise CustomExceptions::ScanSolo::DeliveryInsideTransaction if ActiveRecord::Base.connection.current_transaction.joinable?
    return if message && recorded?

    Messages::MessageBuilder.new(nil, opportunity.conversation, { content: note, private: true }).perform
    ScanSolo::AuditLogger.record!(
      subject: opportunity, event_type: EVENT, correlation_id: quote_request.correlation_id,
      payload: { quote_request_id: quote_request.id, opportunity_id: opportunity.id,
                 template_version: ScanSolo::Quote::RequestEmail::TEMPLATE_VERSION, recipient: recipient,
                 message_id: message&.id, result: reason }
    )
  end

  private

  attr_reader :opportunity, :quote_request, :reason, :message

  def recorded?
    ScanSolo::AuditEvent.where(event_type: EVENT, correlation_id: quote_request.correlation_id)
                        .exists?(['payload @> ?', { message_id: message.id }.to_json])
  end

  def note
    email_conversation = quote_request.email_conversation
    link = ScanSolo::Quote::EmailComposer.conversation_url(email_conversation.account_id, email_conversation.display_id)
    I18n.t('scan_solo.quote.request_email.failure_note', reason: reason, link: link)
  end

  # The failed message's recipient (case B) or the published one (case A).
  def recipient
    message&.content_attributes&.dig('to_emails', 0) || ScanSolo::AiAgentConfig.published_for(opportunity.account).quote_recipient_email
  end
end
