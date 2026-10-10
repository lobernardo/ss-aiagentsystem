# RF-14 / RF-19 / CT-03 / CT-06 / RNF-03..RNF-05: the sole path of the quote
# request update e-mail, run by ScanSolo::QuoteRequestUpdateJob at the end of
# the fixed update window.
#
# 1. Under the request lock the window is closed (a later change opens a new
#    one); nothing goes out unless the request is still `awaiting_reply` /
#    `correction_requested` (checked at send time) and has a sent e-mail with
#    its rendered snapshot (the comparison base, RF-20).
# 2. A fresh RequestEmail::Snapshot with no rendered difference from the last
#    e-mail sent sends nothing.
# 3. The version is claimed, under the request lock, by the unique
#    (quote_request_id, version_digest) row: a version already claimed (sent, or in flight on another thread)
#    sends nothing. A post that raises releases the claim, so the job retry
#    sends it once (RF-18 case A).
# 4. Outside any transaction (RNF-04) the CT-03 e-mail is posted in the
#    request thread (native `Re: <mail_subject>`) with the new attachments up
#    to 15 MiB; then the message, the new comparison base and
#    `quote_request.update_sent` (CT-06 payload) are recorded.
# No request or thread is created, the status never changes and the customer
# is never notified (OC/RF-53).
class ScanSolo::Quote::UpdateService
  ORIGIN = 'quote_request_update'.freeze
  EVENT = 'quote_request.update_sent'.freeze

  def self.call(quote_request:)
    new(quote_request: quote_request).call
  end

  def initialize(quote_request:)
    @quote_request = quote_request
  end

  def call
    return unless close_window!

    snapshot = ScanSolo::Quote::RequestEmail::Snapshot.call(
      opportunity: quote_request.opportunity, config: ScanSolo::AiAgentConfig.published_for(quote_request.account)
    )
    return unless ScanSolo::Quote::RequestEmail.changed?(snapshot, quote_request.rendered_snapshot)

    settings = ScanSolo::Quote::Mailbox.resolve!(quote_request.account)
    digest = Digest::SHA256.hexdigest(snapshot.to_json)
    update = claim!(digest)
    deliver!(update, settings, snapshot, digest) if update
  end

  private

  attr_reader :quote_request

  def close_window!
    quote_request.with_lock do
      quote_request.update!(update_window_ends_at: nil)
      quote_request.open? && quote_request.request_message_id.present? && quote_request.rendered_snapshot.present?
    end
  end

  # Serialized by the request lock; the unique index stays the database guarantee.
  def claim!(digest)
    quote_request.with_lock do
      next if quote_request.updates.exists?(version_digest: digest)

      quote_request.updates.create!(account: quote_request.account, version_digest: digest)
    end
  end

  def deliver!(update, settings, snapshot, digest)
    message = post!(update, settings, snapshot)
    update.update!(message: message, sent_at: Time.current)
    quote_request.update!(rendered_snapshot: snapshot, rendered_digest: digest)
    ScanSolo::AuditLogger.record!(
      subject: quote_request.opportunity, event_type: EVENT, correlation_id: quote_request.correlation_id,
      payload: { quote_request_id: quote_request.id, opportunity_id: quote_request.opportunity_id,
                 template_version: ScanSolo::Quote::RequestEmail::TEMPLATE_VERSION, recipient: settings.recipient,
                 message_id: message.id, result: 'sent' }
    )
  end

  def post!(update, settings, snapshot)
    rendered = ScanSolo::Quote::RequestEmail.render_update(snapshot: snapshot, previous: quote_request.rendered_snapshot)
    ScanSolo::Quote::EmailThread.post!(
      conversation: quote_request.email_conversation, recipient: settings.recipient, email: rendered.email,
      attachments: Attachment.where(id: rendered.attachment_ids).order(:id).map { |attachment| attachment.file.blob },
      additional_attributes: { 'scansolo_origin' => ORIGIN }
    )
  rescue StandardError
    update.destroy!
    raise
  end
end
