class ScanSolo::AiAgentConfigPolicy < ScanSolo::ApplicationPolicy
  def show?
    true
  end

  def draft?
    true
  end

  def publish?
    true
  end
end
