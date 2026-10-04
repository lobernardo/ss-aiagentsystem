# RF-12 / RF-13 / RF-14 / RF-15 / RF-22 / RF-53: the automatic quote request
# of a concluded qualification whose next action is `proposta`.
#
# 1. Eligibility is revalidated in the database (a rolled-back attempt or a
#    stale job never requests); a request already sent only resumes the
#    customer notice (step 5).
# 2. The quote inbox and recipient come from the published config
#    (ScanSolo::Quote::Mailbox). A misconfigured inbox records
#    `quote_request.misconfigured`, reports to the tracker and stops, with no
#    request and no message; the qualification and stage stay as they are.
# 3. Under the opportunity lock (shared with the manual resend), the single
#    request of the opportunity (unique index) and its native e-mail thread
#    are created in one transaction.
# 4. `deliver!` (reused by the manual resend) posts the CT-03 e-mail only
#    after commit (RNF-01), stores the message id and records
#    `quote_request.sent` with the request's correlation id (RF-22, RNF-09).
# 5. The RF-53 notice is posted once to the customer conversation, guarded by
#    `customer_notice_message_id`: never repeated by later turns, job retries
#    or resends. Its `scansolo_origin` keeps it out of the implicit takeover.
class ScanSolo::Quote::RequestService
  NOTICE_ORIGIN = 'quote_notice'.freeze

  def self.call(opportunity:)
    new.call(opportunity: opportunity)
  end

  def call(opportunity:)
    lead_state = opportunity.lead_state
    return unless lead_state.concluida? && lead_state.next_action == 'proposta'
    return post_customer_notice!(opportunity.quote_request) if opportunity.quote_request&.request_message_id.present?

    settings = resolve_settings!(opportunity)
    return if settings.nil?

    quote_request = open_request!(opportunity, settings)
    deliver!(quote_request: quote_request, settings: settings) if quote_request
  end

  def deliver!(quote_request:, settings:)
    message = ScanSolo::Quote::EmailThread.post!(
      conversation: quote_request.email_conversation, recipient: settings.recipient, email: compose(quote_request.opportunity)
    )
    quote_request.update!(request_message_id: message.id, sent_at: Time.current)
    ScanSolo::AuditLogger.record!(
      subject: quote_request.opportunity, event_type: 'quote_request.sent', correlation_id: quote_request.correlation_id,
      payload: { quote_request_id: quote_request.id, message_id: message.id, recipient: settings.recipient }
    )
    post_customer_notice!(quote_request)
  end

  private

  def resolve_settings!(opportunity)
    ScanSolo::Quote::Mailbox.resolve!(opportunity.account)
  rescue CustomExceptions::ScanSolo::QuoteInboxMisconfigured => e
    ScanSolo::AuditLogger.record!(
      subject: opportunity, event_type: 'quote_request.misconfigured', correlation_id: SecureRandom.uuid, payload: { reason: e.reason }
    )
    ChatwootExceptionTracker.new(e, account: opportunity.account).capture_exception
    nil
  end

  def open_request!(opportunity, settings)
    ActiveRecord::Base.transaction do
      opportunity.lock!
      next if ScanSolo::QuoteRequest.exists?(opportunity_id: opportunity.id)

      quote_request = ScanSolo::QuoteRequest.create!(
        account: opportunity.account, opportunity: opportunity, status: :awaiting_reply, correlation_id: SecureRandom.uuid
      )
      conversation = ScanSolo::Quote::EmailThread.open!(
        inbox: settings.inbox, recipient: settings.recipient, subject: compose(opportunity).subject, marker: 'quote_request'
      )
      quote_request.update!(email_conversation: conversation)
      quote_request
    end
  end

  def compose(opportunity)
    config = ScanSolo::AiAgentConfig.published_for(opportunity.account)
    ScanSolo::Quote::EmailComposer.request(
      opportunity: opportunity, projection: ScanSolo::LeadState::Projection.call(opportunity: opportunity, config: config)
    )
  end

  def post_customer_notice!(quote_request)
    return unless quote_request.awaiting_reply? && quote_request.request_message_id.present?

    quote_request.with_lock do
      next if quote_request.customer_notice_message_id.present?

      conversation = quote_request.opportunity.conversation
      notice = conversation.messages.create!(
        account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :outgoing,
        content: I18n.t('scan_solo.quote.customer_notice'), additional_attributes: { 'scansolo_origin' => NOTICE_ORIGIN }
      )
      quote_request.update!(customer_notice_message_id: notice.id)
    end
  end
end
