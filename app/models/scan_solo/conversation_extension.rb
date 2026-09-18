# == Schema Information
#
# Table name: scan_solo_conversation_extensions
#
#  id               :bigint           not null, primary key
#  ai_control_state :integer          default("ai_active"), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  conversation_id  :bigint           not null
#
# Indexes
#
#  index_scan_solo_conversation_extensions_on_conversation_id  (conversation_id) UNIQUE
#
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
