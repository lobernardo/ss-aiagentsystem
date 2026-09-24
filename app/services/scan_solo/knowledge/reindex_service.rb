# Explicit reindex/retry of a knowledge source (RF-31, RF-44): marks it
# `pending` and enqueues ScanSolo::KnowledgeIngestionJob -- the same path a
# create or content change takes. IngestionService's embed-then-replace
# keeps a second run from duplicating chunks. Records one
# `knowledge_source.reindexed` audit event (RF-50).
class ScanSolo::Knowledge::ReindexService
  def self.call(source:, actor:)
    ScanSolo::AuditLogger.record!(
      subject: source, event_type: 'knowledge_source.reindexed', actor: actor, correlation_id: SecureRandom.uuid,
      payload: { title: source.title }
    )
    source.enqueue_ingestion!
    source
  end
end
