# Chunks a knowledge source's content and embeds each chunk through the
# existing PostgreSQL + pgvector/neighbor stack (RF-28), recording the
# indexing state on the source (RF-44): `indexing` while it runs, then
# `indexed` with `indexed_at`/`chunk_count`, or `failed` with a pt-BR
# `index_error`.
#
# Every embedding is computed before the old chunks are touched, and the
# replacement happens in one transaction, so an embedding outage leaves the
# previous chunks searchable and re-running ingestion never duplicates rows.
# A source that yields no chunk (empty content, attachment without
# extractable text) is `failed`, never `indexed` (RF-45).
class ScanSolo::Knowledge::IngestionService
  CHUNK_SIZE = 500
  WRAP_PATTERN = /.{1,#{CHUNK_SIZE}}(?:\s|\z)/m
  EMPTY_CONTENT_ERROR = 'A fonte não tem texto para indexar.'.freeze
  ATTACHMENT_ONLY_ERROR = 'O anexo não tem texto extraível; cole o conteúdo do documento no campo de conteúdo.'.freeze
  INDEXING_ERROR = 'Não foi possível indexar a fonte (%<error>s). Tente reindexar mais tarde.'.freeze

  def self.call(source:, embedding_provider: ScanSolo::Knowledge::EmbeddingService)
    new(source: source, embedding_provider: embedding_provider).call
  end

  def initialize(source:, embedding_provider: ScanSolo::Knowledge::EmbeddingService)
    @source = source
    @embedding_provider = embedding_provider
  end

  def call
    source.update!(index_status: :indexing, index_error: nil)

    chunk_texts = chunk(source.content.to_s)
    return fail!(source.file.attached? ? ATTACHMENT_ONLY_ERROR : EMPTY_CONTENT_ERROR) if chunk_texts.empty?

    replace_chunks!(chunk_texts)
    source
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: source.account).capture_exception
    fail!(format(INDEXING_ERROR, error: e.class.name))
  end

  private

  attr_reader :source, :embedding_provider

  # Embeds everything first, so a provider failure never touches the current chunks.
  def replace_chunks!(chunk_texts)
    embedded = chunk_texts.map { |text| [text, embedding_provider.call(content: text, account: source.account)] }

    ActiveRecord::Base.transaction do
      source.knowledge_chunks.destroy_all
      embedded.each_with_index do |(text, embedding), index|
        source.knowledge_chunks.create!(content: text, position: index, embedding: embedding)
      end
      source.update!(index_status: :indexed, indexed_at: Time.current, chunk_count: embedded.size)
    end
  end

  def fail!(message)
    source.update!(index_status: :failed, index_error: message)
    source
  end

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
