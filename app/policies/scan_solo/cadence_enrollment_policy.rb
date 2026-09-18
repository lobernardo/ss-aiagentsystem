# RF-68/CT-06: manual cadence enrollment is only authorized for an account
# administrator; pause/resume/cancel on an existing enrollment follow the
# same permissive read/write pattern as the rest of the ScanSolo::
# namespace's account-scoped resources.
class ScanSolo::CadenceEnrollmentPolicy < ScanSolo::ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    administrator?
  end

  def pause?
    true
  end

  def resume?
    true
  end

  def cancel?
    true
  end

  private

  def administrator?
    account_user&.administrator? || false
  end
end
