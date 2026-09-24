class ScanSolo::Eligibility
  Result = Struct.new(:eligible?, :reason, keyword_init: true)

  def self.for_message(message)
    for_inbox(account: message.account, inbox: message.inbox)
  end

  def self.for_inbox(account:, inbox:)
    return Result.new(eligible?: false, reason: 'scansolo_disabled') unless account.scansolo_enabled?

    config = ScanSolo::AiAgentConfig.published_for(account)
    return Result.new(eligible?: false, reason: 'config_unavailable') unless config&.enabled?
    unless inbox.account_id == account.id && config.allowed_inbox_ids.include?(inbox.id)
      return Result.new(eligible?: false, reason: 'inbox_not_allowlisted')
    end
    return Result.new(eligible?: false, reason: 'inbox_has_active_bot') if inbox.active_bot?

    Result.new(eligible?: true)
  end
end
