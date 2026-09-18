class ScanSolo::AiTurnPolicy < ScanSolo::ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end
end
