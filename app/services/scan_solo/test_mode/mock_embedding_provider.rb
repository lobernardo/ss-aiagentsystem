# Deterministic fake embedding for knowledge ingestion test mode (RF-25,
# reusing T21's mock-provider pattern): zero calls to any real embedding
# transport. WebMock (spec/spec_helper.rb) already blocks any non-localhost
# HTTP request, so this class is pure Ruby and requires no production LLM
# credential. Same content always yields the same vector, so tests asserting
# nearest-neighbor ranking stay deterministic.
class ScanSolo::TestMode::MockEmbeddingProvider
  DIMENSIONS = 1536

  # `account:` is accepted (unused) only to keep the same call signature as
  # ScanSolo::Knowledge::EmbeddingService, so IngestionService can inject
  # either interchangeably.
  def self.call(content:, account: nil) # rubocop:disable Lint/UnusedMethodArgument
    new.call(content: content)
  end

  def call(content:)
    rng = Random.new(Digest::SHA256.hexdigest(content.to_s).to_i(16))
    Array.new(DIMENSIONS) { rng.rand(-1.0..1.0) }
  end
end
