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

  def approve?
    administrator?
  end

  def retry?
    administrator?
  end

  def send?
    administrator? || record.opportunity.owner_id == user.id
  end
end
