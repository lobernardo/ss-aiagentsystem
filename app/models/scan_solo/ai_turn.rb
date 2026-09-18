# == Schema Information
#
# Table name: scan_solo_ai_turns
#
#  id                  :bigint           not null, primary key
#  action_evidence     :jsonb            not null
#  context_snapshot    :jsonb            not null
#  cost_estimate       :decimal(10, 6)
#  failure_reason      :text
#  guardrail_outcome   :jsonb            not null
#  input_tokens        :integer
#  invocation_status   :integer          default("pending"), not null
#  knowledge_evidence  :jsonb            not null
#  latency_ms          :integer
#  model_provider      :string
#  model_reference     :string
#  output_tokens       :integer
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  conversation_id     :bigint           not null
#  correlation_id      :string           not null
#  message_id          :bigint           not null
#  response_message_id :bigint
#
# Indexes
#
#  index_scan_solo_ai_turns_on_conversation_id      (conversation_id)
#  index_scan_solo_ai_turns_on_correlation_id       (correlation_id) UNIQUE
#  index_scan_solo_ai_turns_on_message_id           (message_id) UNIQUE
#  index_scan_solo_ai_turns_on_response_message_id  (response_message_id)
#
class ScanSolo::AiTurn < ApplicationRecord
  self.table_name = 'scan_solo_ai_turns'

  belongs_to :message
  belongs_to :conversation
  belongs_to :response_message, class_name: 'Message', optional: true

  enum invocation_status: {
    pending: 0,
    suppressed: 1,
    succeeded: 2,
    failed: 3
  }

  validates :message_id, uniqueness: true
  validates :correlation_id, presence: true, uniqueness: true
end
