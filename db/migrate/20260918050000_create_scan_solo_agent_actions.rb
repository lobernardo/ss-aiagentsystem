# Additive registry table for T37/T38: every invocable agent action is a
# row here with exactly one classification (RF-45) and a JSON schema the
# executor (T38) validates structured parameters against before any side
# effect runs (RF-47).
class CreateScanSoloAgentActions < ActiveRecord::Migration[7.1]
  def change
    create_table :scan_solo_agent_actions do |t|
      t.string :action_id, null: false
      t.integer :classification, null: false
      t.jsonb :schema, null: false, default: {}

      t.timestamps
    end

    add_index :scan_solo_agent_actions, :action_id, unique: true
  end
end
