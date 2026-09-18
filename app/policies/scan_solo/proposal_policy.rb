class ScanSolo::ProposalPolicy < ScanSolo::ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def generate?
    true
  end

  def approve?
    true
  end

  def send?
    true
  end
end
