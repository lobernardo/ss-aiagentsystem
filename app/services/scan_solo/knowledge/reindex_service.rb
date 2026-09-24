# Explicit reindex/retry of a knowledge source (RF-31, RF-44): marks it
# `pending` and enqueues ScanSolo::KnowledgeIngestionJob -- the same path a
# create or content change takes. IngestionService's embed-then-replace
# keeps a second run from duplicating chunks.
class ScanSolo::Knowledge::ReindexService
  def self.call(source:)
    source.enqueue_ingestion!
    source
  end
end
