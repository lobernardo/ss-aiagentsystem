# Chunks a knowledge source's content and embeds each chunk through the
# existing PostgreSQL + pgvector/neighbor stack (RF-28). Replaces the
# source's chunks inside one transaction rather than appending to them, so
# re-running ingestion (including via ReindexService, RF-31) always leaves
# exactly the current content's chunk set — never a duplicate.
class ScanSolo::Knowledge::IngestionService
  CHUNK_SIZE = 500
  WRAP_PATTERN = /.{1,#{CHUNK_SIZE}}(?:\s|\z)/m

  def self.call(source:, embedding_provider: ScanSolo::Knowledge::EmbeddingService)
    new(source: source, embedding_provider: embedding_provider).call
  end

  def initialize(source:, embedding_provider: ScanSolo::Knowledge::EmbeddingService)
    @source = source
    @embedding_provider = embedding_provider
  end

  def call
    chunk_texts = chunk(source.content.to_s)

    ActiveRecord::Base.transaction do
      source.knowledge_chunks.destroy_all
      chunk_texts.each_with_index do |text, index|
        embedding = embedding_provider.call(content: text, account: source.account)
        source.knowledge_chunks.create!(content: text, position: index, embedding: embedding)
      end
    end

    source.knowledge_chunks.reload
  end

  private

  attr_reader :source, :embedding_provider

  def chunk(text)
    text.strip
        .split(/\n{2,}/)
        .flat_map { |paragraph| wrap(paragraph) }
        .reject(&:blank?)
  end

  def wrap(paragraph)
    paragraph.scan(WRAP_PATTERN).map(&:strip).reject(&:blank?)
  end
end
