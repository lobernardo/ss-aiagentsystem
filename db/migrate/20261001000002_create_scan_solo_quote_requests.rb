class CreateScanSoloQuoteRequests < ActiveRecord::Migration[7.2]
  def change
    create_table :scan_solo_quote_requests do |t|
      t.references :account, null: false
      t.references :opportunity, null: false, index: { unique: true }, foreign_key: { to_table: :scan_solo_pipeline_opportunities }
      t.bigint :email_conversation_id, index: { unique: true }
      t.bigint :request_message_id
      t.bigint :reply_message_id
      t.bigint :customer_notice_message_id
      t.integer :status, null: false, default: 0
      t.string :correlation_id, null: false, index: { unique: true }
      t.jsonb :commercial, null: false, default: {}
      t.datetime :sent_at
      t.datetime :replied_at

      t.timestamps
    end
  end
end
