class ScanSolo::ProposalPolicy < ScanSolo::ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def generate?
    account_user.present?
  end

  # RF-04/RF-05/RF-15: the published commercial user acts on proposals besides administrators.
  def approve?
    administrator? || commercial_user?
  end

  def reject?
    administrator? || commercial_user?
  end

  def retry?
    administrator? || commercial_user?
  end

  def send?
    administrator? || record.opportunity.owner_id == user.id
  end

  private

  def commercial_user?
    ScanSolo::AiAgentConfig.published_for(account)&.commercial_user_id == user.id
  end
end
