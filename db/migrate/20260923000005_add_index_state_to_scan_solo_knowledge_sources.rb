class AddIndexStateToScanSoloKnowledgeSources < ActiveRecord::Migration[7.2]
  def change
    add_column :scan_solo_knowledge_sources, :index_status, :integer, null: false, default: 0
    add_column :scan_solo_knowledge_sources, :index_error, :text
    add_column :scan_solo_knowledge_sources, :indexed_at, :datetime
    add_column :scan_solo_knowledge_sources, :chunk_count, :integer, null: false, default: 0
  end
end
