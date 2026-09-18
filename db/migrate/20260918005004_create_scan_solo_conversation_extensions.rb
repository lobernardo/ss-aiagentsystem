class CreateScanSoloConversationExtensions < ActiveRecord::Migration[7.1]
  def change
    create_table :scan_solo_conversation_extensions do |t|
      t.references :conversation, null: false, index: { unique: true }
      t.integer :ai_control_state, null: false, default: 0

      t.timestamps
    end
  end
end
