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
end
