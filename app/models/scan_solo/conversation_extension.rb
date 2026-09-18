class ScanSolo::ConversationExtension < ApplicationRecord
  self.table_name = 'scan_solo_conversation_extensions'

  belongs_to :conversation

  enum ai_control_state: {
    ai_active: 0,
    handoff_requested: 1,
    awaiting_human: 2,
    human_active: 3,
    paused: 4,
    closed: 5
  }

  validates :conversation_id, uniqueness: true

  def self.resolve_for(conversation)
    find_or_create_by!(conversation: conversation)
  end
end
