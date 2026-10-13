# CT-05: any account user reads the active template; only administrators upload.
class ScanSolo::ProposalTemplatePolicy < ScanSolo::ApplicationPolicy
  def show?
    true
  end

  def create?
    administrator?
  end
end
