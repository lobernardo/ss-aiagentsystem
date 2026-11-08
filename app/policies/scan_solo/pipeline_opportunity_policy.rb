class ScanSolo::PipelineOpportunityPolicy < ScanSolo::ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    account_user.present?
  end

  def update?
    true
  end

  def stage_transitions?
    true
  end

  # CT-03 / RF-15: any member of the account marks a proposal as sent manually.
  def handled_manually?
    account_user.present?
  end
end
