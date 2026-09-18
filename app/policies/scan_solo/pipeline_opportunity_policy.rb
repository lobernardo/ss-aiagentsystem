class ScanSolo::PipelineOpportunityPolicy < ScanSolo::ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def update?
    true
  end

  def stage_transitions?
    true
  end
end
