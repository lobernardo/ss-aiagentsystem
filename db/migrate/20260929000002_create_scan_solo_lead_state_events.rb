class CreateScanSoloLeadStateEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :scan_solo_lead_state_events do |t|
      t.references :lead_state, null: false, foreign_key: { to_table: :scan_solo_lead_states }
      t.string :subject, null: false
      t.string :key
      t.text :previous_value
      t.string :previous_status
      t.text :new_value
      t.string :new_status
      t.bigint :source_message_id
      t.bigint :source_attachment_id
      t.datetime :created_at, null: false
    end
  end
end
