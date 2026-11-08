class CreateScanSoloReportSnapshots < ActiveRecord::Migration[7.2]
  def change
    create_table :scan_solo_report_snapshots do |t|
      t.references :account, null: false, index: false, foreign_key: true
      t.date :week_start, null: false
      t.jsonb :payload, null: false
      t.datetime :generated_at, null: false

      t.timestamps
    end
    add_index :scan_solo_report_snapshots, [:account_id, :week_start], unique: true
  end
end
