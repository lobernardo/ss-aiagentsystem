class CreateScanSoloKnowledgeChunks < ActiveRecord::Migration[7.1]
  def change
    create_table :scan_solo_knowledge_chunks do |t|
      t.references :source, null: false, index: true, foreign_key: { to_table: :scan_solo_knowledge_sources }
      t.text :content, null: false
      t.integer :position, null: false, default: 0

      t.timestamps
    end
  end
end
