# RF-54: return-to-AI requires the exact same role/permission level
# authorized to take over a conversation (the assigned agent or an account
# administrator) -- both queries below share one authorization check so
# there is no separate authorization concept for either direction.
class ScanSolo::HandoffPolicy < ScanSolo::ApplicationPolicy
  def takeover?
    assigned_agent_or_administrator?
  end

  def return_to_ai?
    assigned_agent_or_administrator?
  end

  private

  def assigned_agent_or_administrator?
    return false if user.blank?

    administrator? || assigned_agent?
  end

  def administrator?
    account_user&.administrator? || false
  end

  def assigned_agent?
    record.assignee_id.present? && record.assignee_id == user.id
  end
end
