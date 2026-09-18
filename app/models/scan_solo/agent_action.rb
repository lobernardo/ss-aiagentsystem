# Registered action definitions consumed by the deterministic executor
# (T38). Every action has exactly one classification from the fixed set
# below (RF-45), mirroring AutomationRule's closed-vocabulary validation
# style (verified app/models/automation_rule.rb) without touching
# AutomationRule itself.
# == Schema Information
#
# Table name: scan_solo_agent_actions
#
#  id             :bigint           not null, primary key
#  classification :integer          not null
#  schema         :jsonb            not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  action_id      :string           not null
#
# Indexes
#
#  index_scan_solo_agent_actions_on_action_id  (action_id) UNIQUE
#
class ScanSolo::AgentAction < ApplicationRecord
  self.table_name = 'scan_solo_agent_actions'

  has_many :executions,
           class_name: 'ScanSolo::AgentActionExecution',
           foreign_key: :action_id,
           primary_key: :action_id,
           inverse_of: :agent_action,
           dependent: :restrict_with_exception

  enum classification: {
    read_only: 0,
    automatic: 1,
    requires_confirmation: 2,
    disabled: 3
  }

  validates :action_id, presence: true, uniqueness: true
  validates :classification, presence: true
end
