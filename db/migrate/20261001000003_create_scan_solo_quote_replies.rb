class CreateScanSoloQuoteReplies < ActiveRecord::Migration[7.2]
  def change
    create_table :scan_solo_quote_replies do |t|
      t.references :account, null: false, index: false
      t.bigint :message_id, null: false, index: { unique: true }
      t.bigint :conversation_id
      t.references :quote_request, foreign_key: { to_table: :scan_solo_quote_requests }
      t.integer :kind
      t.integer :status, null: false, default: 0
      t.references :resolved_by, foreign_key: { to_table: :users }
      t.datetime :resolved_at

      t.timestamps
    end
    add_index :scan_solo_quote_replies, [:account_id, :status]
  end
end
