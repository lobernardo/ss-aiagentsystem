# UI-09: read-only Execuções e auditoria screen, open to any authenticated
# member of an account with ScanSolo enabled (mirrors ScanSolo::AiTurnPolicy).
class ScanSolo::ExecutionPolicy < ScanSolo::ApplicationPolicy
  def index?
    true
  end
end
