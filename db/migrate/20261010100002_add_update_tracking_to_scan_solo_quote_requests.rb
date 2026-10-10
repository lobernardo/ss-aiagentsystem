class AddUpdateTrackingToScanSoloQuoteRequests < ActiveRecord::Migration[7.2]
  def change
    add_column :scan_solo_quote_requests, :rendered_snapshot, :jsonb
    add_column :scan_solo_quote_requests, :rendered_digest, :string
    add_column :scan_solo_quote_requests, :update_window_ends_at, :datetime

    create_table :scan_solo_quote_request_updates do |t|
      t.references :account, null: false
      t.references :quote_request, null: false, index: false, foreign_key: { to_table: :scan_solo_quote_requests }
      t.string :version_digest, null: false
      t.bigint :message_id
      t.datetime :sent_at

      t.timestamps
    end
    add_index :scan_solo_quote_request_updates, [:quote_request_id, :version_digest],
              unique: true, name: 'index_scan_solo_quote_request_updates_on_request_and_digest'
  end
end
