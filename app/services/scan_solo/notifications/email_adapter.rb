# RF-37 / RF-42: default CT-07 adapter. Sends the negotiation e-mail through
# the published quote inbox to the published commercial recipient, in its own
# thread marked `negotiation_notification` (replies to it are never read as
# quote replies). A misconfigured inbox answers failure with its reason.
class ScanSolo::Notifications::EmailAdapter
  MARKER = 'negotiation_notification'.freeze

  def self.call(payload:, **)
    settings = ScanSolo::Quote::Mailbox.resolve!(Account.find(payload[:account_id]))
    email = ScanSolo::Quote::EmailComposer.negotiation(payload: payload)
    conversation = ScanSolo::Quote::EmailThread.open!(inbox: settings.inbox, recipient: settings.recipient, subject: email.subject, marker: MARKER)
    ScanSolo::Quote::EmailThread.post!(conversation: conversation, recipient: settings.recipient, email: email)

    ScanSolo::Notifications::Publisher::Result.new(success: true, reason: nil)
  rescue CustomExceptions::ScanSolo::QuoteInboxMisconfigured => e
    ScanSolo::Notifications::Publisher::Result.new(success: false, reason: e.reason)
  end
end
