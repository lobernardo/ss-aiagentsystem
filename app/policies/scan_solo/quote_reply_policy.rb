# CT-08: pending quote replies are handled by account administrators or by
# native members of the published quote inbox.
class ScanSolo::QuoteReplyPolicy < ScanSolo::ApplicationPolicy
  def index?
    administrator? || quote_inbox_member?
  end

  def link?
    index?
  end

  def discard?
    index?
  end

  private

  def quote_inbox_member?
    quote_inbox_id = ScanSolo::AiAgentConfig.published_for(account)&.quote_inbox_id
    quote_inbox_id.present? && InboxMember.exists?(inbox_id: quote_inbox_id, user_id: user.id)
  end
end
