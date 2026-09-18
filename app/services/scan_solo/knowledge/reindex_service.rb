# Idempotent reindex/retry of a knowledge source (RF-31). Delegates to
# IngestionService, whose ingest-then-replace transaction already makes a
# second run leave the same chunk set rather than duplicating rows — this
# class exists as the explicit, separately-named entry point the Knowledge
# screen's "reindex" action (UI-05) and controller (T27) invoke.
class ScanSolo::Knowledge::ReindexService
  def self.call(source:, embedding_provider: ScanSolo::Knowledge::EmbeddingService)
    ScanSolo::Knowledge::IngestionService.call(source: source, embedding_provider: embedding_provider)
  end
end
