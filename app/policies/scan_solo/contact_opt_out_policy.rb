class ScanSolo::ContactOptOutPolicy < ScanSolo::ApplicationPolicy
  def show?
    true
  end

  def destroy?
    administrator?
  end
end
