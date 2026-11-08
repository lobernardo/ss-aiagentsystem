# RF-11: the read-only Relatórios report (CT-01) is open to any authenticated
# member of an account with ScanSolo enabled (mirrors ScanSolo::ExecutionPolicy).
class ScanSolo::ReportPolicy < ScanSolo::ApplicationPolicy
  def index?
    true
  end
end
