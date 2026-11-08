class AddHandledManuallyToScanSoloQuoteRequests < ActiveRecord::Migration[7.2]
  def change
    add_column :scan_solo_quote_requests, :handled_manually_at, :datetime
    add_reference :scan_solo_quote_requests, :handled_manually_by, foreign_key: { to_table: :users }, null: true
  end
end
