# RF-57: versioned/configurable cadence schedule per pipeline stage. Additive
# table only -- a new schedule for a stage is a new version row, never an
# edit of an existing one, so an enrollment's snapshot stays reproducible.
class CreateScanSoloCadenceDefinitions < ActiveRecord::Migration[7.1]
  def change
    create_table :scan_solo_cadence_definitions do |t|
      t.string :stage, null: false
      t.integer :version, null: false, default: 1
      t.jsonb :offsets, null: false, default: []
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :scan_solo_cadence_definitions, %i[stage version], unique: true
  end
end
