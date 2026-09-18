# Additive column on the ScanSolo-owned scan_solo_knowledge_chunks table,
# using the existing `vector` column type/extension (already enabled by an
# upstream Community migration for Captain/help-center embeddings) — no new
# extension, no proprietary vector store (RF-28).
#
# Deliberately no ivfflat index: that index type trains its clusters from
# whatever rows exist at CREATE INDEX time, which here is zero — on a
# freshly migrated table an ivfflat index over embeddings stays degenerate
# (verified: nearest_neighbors silently returns no rows) until an explicit
# REINDEX. Exact nearest_neighbors search over a plain vector column stays
# correct at ScanSolo's expected per-account knowledge-base scale.
class AddEmbeddingToScanSoloKnowledgeChunks < ActiveRecord::Migration[7.1]
  def change
    add_column :scan_solo_knowledge_chunks, :embedding, :vector, limit: 1536
  end
end
