# Execution-log row for a single invocation of a registered ScanSolo::AgentAction
# through the deterministic executor (T38). One row per idempotency key
# (RNF-01); status moves pending -> executed/failed, or stays pending
# forever for a requires_confirmation action awaiting confirmation (RF-49).
class ScanSolo::AgentActionExecution < ApplicationRecord
  self.table_name = 'scan_solo_agent_action_executions'

  belongs_to :agent_action,
             class_name: 'ScanSolo::AgentAction',
             foreign_key: :action_id,
             primary_key: :action_id,
             inverse_of: :executions
  belongs_to :turn, class_name: 'ScanSolo::AiTurn', optional: true
  belongs_to :audit_event, class_name: 'ScanSolo::AuditEvent', optional: true

  enum status: {
    pending: 0,
    executed: 1,
    failed: 2
  }

  validates :action_id, presence: true
  validates :correlation_id, presence: true
  validates :idempotency_key, presence: true, uniqueness: true
end
