class CreateScanSoloKnowledgeSources < ActiveRecord::Migration[7.1]
  def change
    create_table :scan_solo_knowledge_sources do |t|
      t.references :account, null: false, index: true
      t.references :added_by, index: true
      t.integer :source_type, null: false, default: 0
      t.string :title
      t.text :content
      t.string :origin
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end
  end
end
