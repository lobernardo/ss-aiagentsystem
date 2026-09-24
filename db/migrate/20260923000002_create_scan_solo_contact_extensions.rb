class CreateScanSoloContactExtensions < ActiveRecord::Migration[7.2]
  def change
    create_table :scan_solo_contact_extensions do |t|
      t.references :contact, null: false, foreign_key: true, index: { unique: true }
      t.boolean :opted_out, null: false, default: false
      t.datetime :opted_out_at
      t.string :opted_out_source
      t.timestamps
    end
  end
end
