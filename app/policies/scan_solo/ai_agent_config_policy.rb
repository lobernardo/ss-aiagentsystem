class ScanSolo::AiAgentConfigPolicy < ScanSolo::ApplicationPolicy
  def show?
    true
  end

  def draft?
    administrator?
  end

  def publish?
    administrator?
  end
end
