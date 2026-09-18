# RNF-06: `correlation_id` carries a permanent unique index -- no TTL/expiry
# mechanism of any kind -- so a replayed inbound Make callback is rejected
# indefinitely, not just within a retention window (RF-85, RF-86).
# Webhooks::ScanSolo::MakeController (T68) is the sole writer, inserting
# exactly one row per inbound callback attempt (accepted or rejected) and
# never updating one afterwards -- there is intentionally no `updated_at`,
# mirroring the write-once `scan_solo_audit_events` table.
class CreateScanSoloMakeCallbacks < ActiveRecord::Migration[7.1]
  def change
    create_table :scan_solo_make_callbacks do |t|
      t.string :correlation_id
      t.string :action
      t.boolean :signature_valid, null: false, default: false
      t.boolean :applied, null: false, default: false
      t.string :rejection_reason
      t.jsonb :payload, null: false, default: {}

      t.datetime :created_at, null: false
    end

    add_index :scan_solo_make_callbacks, :correlation_id, unique: true
  end
end
