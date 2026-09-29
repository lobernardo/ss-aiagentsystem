# RF-17..RF-20, RF-18a, RNF-02: reads what an inbound message carries beyond
# its text -- location attachments, PDFs and URLs -- into lead state field
# updates, without writing anything, calling an LLM or making HTTP requests.
#
# - Location → `link_local` from `external_url`, or a Google Maps link built
#   from the coordinates.
# - PDF up to 10 MB and 10 pages → text via `pdf-reader`; a CNPJ, the value
#   after a "razão social" label and after an "endereço" label fill `cnpj`,
#   `empresa` and `endereco_obra`. No OCR: a scanned PDF has no text.
# - URLs in the text: a map URL fills `link_local` (no attachment origin);
#   every URL is returned in `urls` and none is fetched.
#
# Every update is `inferido` (RF-07); the caller writes it through
# ScanSolo::LeadState::Writer. `evidence` has one entry per attachment with
# the reason nothing was extracted (RF-20).
class ScanSolo::AiTurn::AttachmentReader
  MAX_PDF_BYTES = 10.megabytes
  MAX_PDF_PAGES = 10
  URL_PATTERN = %r{https?://[^\s<>"]+}
  MAP_URL_PATTERN = %r{\Ahttps?://(?:(?:www\.)?google\.[a-z.]+/maps|maps\.google\.[a-z.]+|goo\.gl/maps|maps\.app\.goo\.gl)(?:[/?#]|\z)}i
  CNPJ_PATTERN = %r{\d{2}\.?\d{3}\.?\d{3}/?\d{4}-?\d{2}}
  COMPANY_LABEL = /raz[aãÃ]o\s+social\s*:?/i
  ADDRESS_LABEL = /endere[cçÇ]o(?:\s+d[ae]\s+obra)?\s*:?/i

  Result = Struct.new(:updates, :evidence, :urls, keyword_init: true)

  def self.call(message:) = new(message: message).call

  def initialize(message:)
    @message = message
    @updates = []
    @evidence = []
  end

  def call
    message.attachments.sort_by(&:id).each { |attachment| read_attachment(attachment) }
    urls = message.content.to_s.scan(URL_PATTERN).map { |url| url.sub(/[.,;:!?)\]]+\z/, '') }
    urls.grep(MAP_URL_PATTERN).each { |url| updates << { key: 'link_local', value: url, source_attachment_id: nil } }

    Result.new(updates: updates, evidence: evidence, urls: urls)
  end

  private

  attr_reader :message, :updates, :evidence

  def read_attachment(attachment)
    reason = if attachment.location?
               read_location(attachment)
             elsif pdf?(attachment)
               read_pdf(attachment)
             else
               'unsupported_type'
             end

    evidence << { attachment_id: attachment.id, file_type: attachment.file_type, file_name: file_name(attachment),
                  extracted: reason.nil?, reason: reason }
  end

  def read_location(attachment)
    link = attachment.external_url.presence ||
           "https://www.google.com/maps?q=#{attachment.coordinates_lat},#{attachment.coordinates_long}"
    updates << { key: 'link_local', value: link, source_attachment_id: attachment.id }
    nil
  end

  def pdf?(attachment)
    attachment.file? && attachment.file.attached? && attachment.file.content_type == 'application/pdf'
  end

  # Third-party PDFs can break the parser in many ways; any error only
  # skips this attachment (RF-20).
  def read_pdf(attachment)
    return 'too_large' if attachment.file.byte_size > MAX_PDF_BYTES

    text = attachment.file.blob.open do |file|
      reader = PDF::Reader.new(file)
      return 'too_many_pages' if reader.page_count > MAX_PDF_PAGES

      reader.pages.map(&:text).join("\n")
    end
    return 'no_extractable_text' if text.strip.empty?

    extract_fields(text, attachment.id)
    nil
  rescue StandardError => e
    "extraction_error: #{e.class}"
  end

  def extract_fields(text, attachment_id)
    lines = text.lines.map(&:squish)
    {
      'cnpj' => text[CNPJ_PATTERN],
      'empresa' => labeled_value(lines, COMPANY_LABEL),
      'endereco_obra' => labeled_value(lines, ADDRESS_LABEL)
    }.each do |key, value|
      updates << { key: key, value: value, source_attachment_id: attachment_id } if value.present?
    end
  end

  # The text after the label on its line, or the next non-blank line.
  def labeled_value(lines, label)
    index = lines.index { |line| line.match?(label) }
    return if index.nil?

    lines[index].split(label, 2).last.to_s.sub(/\A[\s:–-]+/, '').presence || lines[(index + 1)..].find(&:present?)
  end

  def file_name(attachment)
    attachment.file.filename.to_s if attachment.file.attached?
  end
end
