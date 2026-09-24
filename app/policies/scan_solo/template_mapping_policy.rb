class ScanSolo::TemplateMappingPolicy < ScanSolo::ApplicationPolicy
  def index?
    true
  end

  def update?
    administrator?
  end
end
