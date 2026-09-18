# Execution-log row for a single invocation of a registered ScanSolo::AgentAction
# through the deterministic executor (T38). One row per idempotency key
# (RNF-01); status moves pending -> executed/failed, or stays pending
# forever for a requires_confirmation action awaiting confirmation (RF-49).
# == Schema Information
#
# Table name: scan_solo_agent_action_executions
#
#  id              :bigint           not null, primary key
#  confirmed_at    :datetime
#  idempotency_key :string           not null
#  params          :jsonb            not null
#  status          :integer          default("pending"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  action_id       :string           not null
#  audit_event_id  :bigint
#  correlation_id  :string           not null
#  turn_id         :bigint
#
# Indexes
#
#  index_scan_solo_agent_action_executions_on_action_id        (action_id)
#  index_scan_solo_agent_action_executions_on_audit_event_id   (audit_event_id)
#  index_scan_solo_agent_action_executions_on_correlation_id   (correlation_id)
#  index_scan_solo_agent_action_executions_on_idempotency_key  (idempotency_key) UNIQUE
#  index_scan_solo_agent_action_executions_on_turn_id          (turn_id)
#
# Foreign Keys
#
#  fk_rails_...  (audit_event_id => scan_solo_audit_events.id)
#  fk_rails_...  (turn_id => scan_solo_ai_turns.id)
#
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
