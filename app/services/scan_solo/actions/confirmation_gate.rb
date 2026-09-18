# RF-49: an action classified requires_confirmation never runs its side
# effect without an explicit confirming authorization recorded for that
# invocation. Consulted by ScanSolo::Actions::Executor before it calls the
# side-effect block -- when blocked, the executor leaves the execution row
# pending and the side effect never runs; a later invocation for the same
# idempotency key with confirmed: true clears the gate.
class ScanSolo::Actions::ConfirmationGate
  def self.blocked?(action:, confirmed:)
    action.requires_confirmation? && !confirmed
  end
end
