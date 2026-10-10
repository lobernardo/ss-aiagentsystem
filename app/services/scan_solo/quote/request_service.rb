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
#    are created in one transaction. A request left without
#    `request_message_id` (the e-mail failed after commit) is returned as is,
#    so a job retry sends its e-mail exactly once, with no 2nd request or
#    thread (RF-22 of scansolo-proposta-aprovacao-email).
# 4. `deliver!` (reused by the manual resend, RF-20) renders the CT-01 e-mail
#    from a RequestEmail::Snapshot (no LLM, no HTTP, RF-01) and posts it only
#    after commit (RNF-01, RNF-04) with the selected lead attachments (RF-13).
#    It stores the message id, the rendered snapshot and its SHA-256 digest
#    (the base of the next update e-mail, RF-14/RF-20), closes any update
#    window and records `quote_request.sent` with the request's correlation
#    id and the CT-06 payload (RF-19, RNF-09).
# 5. The RF-53 notice is posted once to the customer conversation, guarded by
#    `customer_notice_message_id`: never repeated by later turns, job retries
#    or resends. Its `scansolo_origin` keeps it out of the implicit takeover.
class ScanSolo::Quote::RequestService
  NOTICE_ORIGIN = 'quote_notice'.freeze
  EMAIL_ORIGIN = 'quote_request_email'.freeze

  Rendered = Struct.new(:email, :blobs, keyword_init: true)
  MISCONFIGURED_EVENT = 'quote_request.misconfigured'.freeze

  def self.call(opportunity:)
    new.call(opportunity: opportunity)
  end

  def call(opportunity:)
    lead_state = opportunity.lead_state
    return unless lead_state.concluida? && lead_state.next_action == 'proposta'
    return post_customer_notice!(opportunity.quote_request) if opportunity.quote_request&.request_message_id.present?

    settings = resolve_settings!(opportunity)
    return if settings.nil?

    snapshot = snapshot(opportunity)
    rendered = render(snapshot)
    quote_request = open_request!(opportunity, settings, rendered.email.subject)
    deliver!(quote_request: quote_request, settings: settings, snapshot: snapshot, rendered: rendered) if quote_request
  end

  # Rendered before the request is opened, so the post follows its commit right away.
  def deliver!(quote_request:, settings:, snapshot: snapshot(quote_request.opportunity), rendered: render(snapshot))
    message = ScanSolo::Quote::EmailThread.post!(
      conversation: quote_request.email_conversation, recipient: settings.recipient, email: rendered.email,
      attachments: rendered.blobs, additional_attributes: { 'scansolo_origin' => EMAIL_ORIGIN }
    )
    quote_request.update!(
      request_message_id: message.id, sent_at: Time.current, rendered_snapshot: snapshot,
      rendered_digest: Digest::SHA256.hexdigest(snapshot.to_json), update_window_ends_at: nil
    )
    ScanSolo::AuditLogger.record!(
      subject: quote_request.opportunity, event_type: 'quote_request.sent', correlation_id: quote_request.correlation_id,
      payload: { quote_request_id: quote_request.id, opportunity_id: quote_request.opportunity_id,
                 template_version: ScanSolo::Quote::RequestEmail::TEMPLATE_VERSION, recipient: settings.recipient,
                 message_id: message.id, result: 'sent' }
    )
    post_customer_notice!(quote_request)
  end

  # RF-14, also recorded by a manual resend on a still invalid config.
  def record_misconfigured!(opportunity, error)
    ScanSolo::AuditLogger.record!(
      subject: opportunity, event_type: MISCONFIGURED_EVENT, correlation_id: SecureRandom.uuid, payload: { reason: error.reason }
    )
    ChatwootExceptionTracker.new(error, account: opportunity.account).capture_exception
  end

  # The single request of the opportunity and its e-mail thread; the caller
  # holds the opportunity lock (the job and the manual resend).
  def create_request!(opportunity, settings, subject = ScanSolo::Quote::RequestEmail.new(snapshot(opportunity)).subject)
    quote_request = ScanSolo::QuoteRequest.create!(
      account: opportunity.account, opportunity: opportunity, status: :awaiting_reply, correlation_id: SecureRandom.uuid
    )
    conversation = ScanSolo::Quote::EmailThread.open!(
      inbox: settings.inbox, recipient: settings.recipient, subject: subject, marker: 'quote_request'
    )
    quote_request.update!(email_conversation: conversation)
    quote_request
  end

  private

  def resolve_settings!(opportunity)
    ScanSolo::Quote::Mailbox.resolve!(opportunity.account)
  rescue CustomExceptions::ScanSolo::QuoteInboxMisconfigured => e
    record_misconfigured!(opportunity, e)
    nil
  end

  def open_request!(opportunity, settings, subject)
    ActiveRecord::Base.transaction do
      opportunity.lock!
      existing = ScanSolo::QuoteRequest.find_by(opportunity_id: opportunity.id)
      next create_request!(opportunity, settings, subject) if existing.nil?

      existing if existing.request_message_id.nil?
    end
  end

  # The RequestEmail result plus the ActiveStorage blobs of its attachments (RF-13).
  def render(snapshot)
    rendered = ScanSolo::Quote::RequestEmail.render(snapshot: snapshot)
    blobs = Attachment.where(id: rendered.attachment_ids).order(:id).map { |attachment| attachment.file.blob }
    Rendered.new(email: rendered.email, blobs: blobs)
  end

  def snapshot(opportunity)
    ScanSolo::Quote::RequestEmail::Snapshot.call(opportunity: opportunity, config: ScanSolo::AiAgentConfig.published_for(opportunity.account))
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
