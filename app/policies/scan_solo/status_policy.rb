class ScanSolo::StatusPolicy < ScanSolo::ApplicationPolicy
  def show?
    administrator?
  end
end
