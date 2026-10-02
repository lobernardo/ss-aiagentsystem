# CT-03 / RF-12 / RF-37 / RF-42: a native e-mail thread of the quote inbox.
# `open!` creates the conversation without a message (so it can join the
# caller's transaction), marked with `scansolo_thread` and the thread
# `mail_subject`. `post!` creates the outgoing message only after commit
# (RNF-01); delivery is the native one (`SendReplyJob` →
# `Email::SendOnEmailService` → `ConversationReplyMailer`, From = channel
# e-mail, native Message-ID for threading).
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

  def self.post!(conversation:, recipient:, email:)
    raise CustomExceptions::ScanSolo::DeliveryInsideTransaction if ActiveRecord::Base.connection.current_transaction.joinable?

    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :outgoing, content: email.text,
      content_attributes: { to_emails: [recipient], email: { html_content: { reply: email.html } } }
    )
  end
end
