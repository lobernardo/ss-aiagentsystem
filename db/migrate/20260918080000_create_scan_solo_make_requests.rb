# RF-84/RF-85: one row per outbound Make integration request (CT-08),
# created by ScanSolo::Make::OutboundRequestService (T67). `correlation_id`
# carries its own unique index so a caller can never issue two outbound
# requests under the same correlation id; `idempotency_key` is attached to
# every outbound HTTP call so Make can dedupe retried deliveries too.
# `status`/`retry_count` feed T70's dead-letter/error visibility query for
# requests that keep failing (RF-86).
class CreateScanSoloMakeRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :scan_solo_make_requests do |t|
      t.references :account, null: false, index: true, foreign_key: true
      t.string :correlation_id, null: false
      t.string :idempotency_key, null: false
      t.string :action, null: false
      t.jsonb :payload, null: false, default: {}
      t.integer :status, null: false, default: 0
      t.integer :retry_count, null: false, default: 0

      t.timestamps
    end

    add_index :scan_solo_make_requests, :correlation_id, unique: true
  end
end
