# CT-03 / RF-12 / RF-37 / RF-42: a native e-mail thread of the quote inbox.
# `open!` creates the conversation without a message (so it can join the
# caller's transaction), marked with `scansolo_thread` and the thread
# `mail_subject`. `post!` creates the outgoing message only after commit
# (RNF-01); delivery is the native one (`SendReplyJob` →
# `Email::SendOnEmailService` → `ConversationReplyMailer`, From = channel
# e-mail, native Message-ID for threading).
# `post!` also takes CC recipients (`content_attributes.cc_emails`, read by
# the mailer), ActiveStorage blobs created as attachments of the same message
# (so `SendReplyJob` already sees them) and the message
# `additional_attributes` (CT-05, CT-06).
class ScanSolo::Quote::EmailThread
  def self.open!(inbox:, recipient:, subject:, marker:)
    contact_inbox = ContactInboxWithContactBuilder.new(
      inbox: inbox, source_id: recipient,
      contact_attributes: { name: I18n.t('scan_solo.quote.email.recipient_contact_name'), email: recipient }
    ).perform

    ConversationBuilder.new(
      params: ActionController::Parameters.new(additional_attributes: { mail_subject: subject, scansolo_thread: marker }),
      contact_inbox: contact_inbox
    ).perform
  end

  # rubocop:disable Metrics/ParameterLists
  def self.post!(conversation:, recipient:, email:, cc: [], attachments: [], additional_attributes: {})
    # rubocop:enable Metrics/ParameterLists
    raise CustomExceptions::ScanSolo::DeliveryInsideTransaction if ActiveRecord::Base.connection.current_transaction.joinable?

    content_attributes = { to_emails: [recipient], email: { html_content: { reply: email.html } } }
    content_attributes[:cc_emails] = cc if cc.present?
    message = conversation.messages.new(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :outgoing, content: email.text,
      content_attributes: content_attributes, additional_attributes: additional_attributes
    )
    attachments.each { |blob| message.attachments.new(account_id: conversation.account_id, file_type: :file, file: blob) }
    message.save!
    message
  end
end
