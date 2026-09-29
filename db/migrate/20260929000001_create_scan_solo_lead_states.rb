class CreateScanSoloLeadStates < ActiveRecord::Migration[7.1]
  def change
    create_table :scan_solo_lead_states do |t|
      t.references :opportunity, null: false, index: { unique: true }, foreign_key: { to_table: :scan_solo_pipeline_opportunities }
      t.string :intent
      t.integer :qualification_status, null: false, default: 0
      t.datetime :qualification_completed_at
      t.string :next_action
      t.datetime :next_action_recorded_at
      t.bigint :next_action_source_message_id
      t.jsonb :authorized_actions, null: false, default: []
      t.jsonb :fields, null: false, default: {}

      t.timestamps
    end
  end
end
