# RF-12 / RF-14 / RF-16 / RF-54: the quote inbox and commercial recipient of
# an account, read only from the published config (a draft edit is ignored
# until publish). No recipient is fixed in code. A missing, non-e-mail or
# allowlisted inbox is a setup bug and fails loudly with its `reason`.
class ScanSolo::Quote::Mailbox
  Settings = Struct.new(:inbox, :recipient, keyword_init: true)

  def self.resolve!(account)
    config = ScanSolo::AiAgentConfig.published_for(account)
    inbox = account.inboxes.find_by(id: config.quote_inbox_id) if config

    raise CustomExceptions::ScanSolo::QuoteInboxMisconfigured, 'quote_inbox_missing' if inbox.nil?
    raise CustomExceptions::ScanSolo::QuoteInboxMisconfigured, 'quote_inbox_not_email' unless inbox.email?
    raise CustomExceptions::ScanSolo::QuoteInboxMisconfigured, 'quote_inbox_allowlisted' if config.allowed_inbox_ids.include?(inbox.id)

    Settings.new(inbox: inbox, recipient: config.quote_recipient_email)
  end
end
