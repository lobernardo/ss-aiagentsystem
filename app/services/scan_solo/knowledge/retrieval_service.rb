# Ranked knowledge retrieval, shared by the canonical AI turn flow (Phase 6)
# and the operator-facing retrieval-test simulator (CT-03, RF-32). Every
# result carries the originating source id as evidence, traceable back to
# its ScanSolo::KnowledgeSource (RF-29). Disabled sources are excluded from
# the eligible scope without deleting their chunks (RF-30). A vector-store
# outage (embedding provider or pgvector query) degrades to empty results
# plus a recorded failure reason instead of raising into the caller's turn
# (RF-34) — the rescue below is scoped to the specific outage-shaped error
# classes, not a broad `rescue StandardError` that could also swallow a
# real application bug.
class ScanSolo::Knowledge::RetrievalService
  DEFAULT_TOP_K = 5
  OUTAGE_ERRORS = [ActiveRecord::StatementInvalid, PG::Error, RubyLLM::Error, RubyLLM::ConfigurationError].freeze

  Result = Struct.new(:chunk_id, :source_id, :source_title, :source_type, :content_snippet, :similarity_score, keyword_init: true)

  def self.call(account:, query:, top_k: DEFAULT_TOP_K, embedding_provider: ScanSolo::Knowledge::EmbeddingService)
    new(account: account, embedding_provider: embedding_provider).call(query: query, top_k: top_k)
  end

  def initialize(account:, embedding_provider: ScanSolo::Knowledge::EmbeddingService)
    @account = account
    @embedding_provider = embedding_provider
  end

  def call(query:, top_k: DEFAULT_TOP_K)
    embedding = embedding_provider.call(content: query, account: account)
    chunks = eligible_scope.nearest_neighbors(:embedding, embedding, distance: 'cosine').limit(top_k)

    { results: chunks.map { |chunk| to_result(chunk) }, failure_reason: nil }
  rescue *OUTAGE_ERRORS => e
    Rails.logger.error("ScanSolo::Knowledge::RetrievalService outage: #{e.class}: #{e.message}")
    { results: [], failure_reason: "#{e.class}: #{e.message}" }
  end

  private

  attr_reader :account, :embedding_provider

  def eligible_scope
    ScanSolo::KnowledgeChunk.joins(:source).merge(ScanSolo::KnowledgeSource.where(account: account, enabled: true))
  end

  def to_result(chunk)
    Result.new(
      chunk_id: chunk.id,
      source_id: chunk.source_id,
      source_title: chunk.source.title,
      source_type: chunk.source.source_type,
      content_snippet: chunk.content,
      similarity_score: (1 - chunk.neighbor_distance.to_f).clamp(0.0, 1.0)
    )
  end
end
