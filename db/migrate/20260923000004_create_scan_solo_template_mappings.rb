class CreateScanSoloTemplateMappings < ActiveRecord::Migration[7.2]
  def change
    create_table :scan_solo_template_mappings do |t|
      t.references :account, null: false, foreign_key: true
      t.string :stage, null: false
      t.integer :step
      t.string :template_name, null: false
      t.string :language, null: false
      t.jsonb :params, null: false, default: []
      t.timestamps
    end

    add_index :scan_solo_template_mappings, %i[account_id stage step], unique: true, nulls_not_distinct: true
  end
end
