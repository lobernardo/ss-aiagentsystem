class CreateScanSoloAuditEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :scan_solo_audit_events do |t|
      t.references :subject, polymorphic: true, null: false, index: false
      t.references :actor, polymorphic: true, index: false
      t.string :event_type, null: false
      t.string :correlation_id, null: false
      t.jsonb :payload, null: false, default: {}

      t.datetime :created_at, null: false
    end

    add_index :scan_solo_audit_events, [:subject_type, :subject_id]
    add_index :scan_solo_audit_events, [:actor_type, :actor_id]
    add_index :scan_solo_audit_events, :correlation_id
    add_index :scan_solo_audit_events, :event_type
  end
end
