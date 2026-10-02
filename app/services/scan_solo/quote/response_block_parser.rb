# CT-04 / RF-17 / RF-18 / RF-21: deterministic read of the commercial reply
# block. Pure: no LLM, no I/O. Labels come from `scan_solo.quote.block.*`.
#
# - Input: the message text; when it is empty, the HTML converted to text
#   with `<br>`/`</p>`/`</li>`/`</div>` as line breaks.
# - Tolerance: case, accents, collapsed spaces, blank lines, bold/bullet
#   markers and `:` with or without spaces. Delimiters are optional.
# - Segmentation: lines starting with `>`, the "Em … escreveu:" / "On …
#   wrote:" header and the delimiters end the current value; a value runs
#   from its label to the next label or one of those boundaries and may span
#   lines. A repeated label starts a new block.
# - The first block (top-down) with at least one filled label is read, so the
#   quoted empty block of the original e-mail is ignored.
# - `total_value`: `R$`? + `1.234,56`-style number (`.` thousands, `,`
#   decimals), > 0. Empty or illegible required values go to `problems`.
class ScanSolo::Quote::ResponseBlockParser
  Result = Data.define(:values, :problems) do
    def valid?
      problems.empty?
    end
  end

  REQUIRED = %i[total_value schedule scope payment_terms].freeze
  VALUE_FORMAT = /\A(?:R\$\s*)?(\d{1,3}(?:\.\d{3})*(?:,\d{2})?|\d+(?:,\d{2})?)\z/i
  QUOTE_HEADER = /\A(?:em|on)\s.*(?:escreveu|wrote):\z/
  LEADING_MARKERS = /\A[\s*_\-•]+/
  HTML_LINE_BREAKS = %r{<br\s*/?>|</p>|</li>|</div>}i

  def self.call(content:, html: nil)
    new(content: content, html: html).call
  end

  def initialize(content:, html:)
    @text = content.presence || html_to_text(html.to_s)
  end

  def call
    fields = blocks.find { |block| block.values.any?(&:present?) } || {}
    values = fields.transform_values(&:presence)
    total_value = parse_amount(values[:total_value]) if values[:total_value]

    values = { total_value: total_value, schedule: values[:schedule], scope: values[:scope], payment_terms: values[:payment_terms],
               notes: values[:notes] }
    Result.new(values: values, problems: REQUIRED.select { |key| values[key].blank? })
  end

  private

  attr_reader :text

  def blocks
    lines = text.split(/\r?\n/)
    blocks = lines.each.with_index.with_object([{}]) { |(line, index), memo| read_line(memo, line, lines[index + 1]) }
    blocks.map { |block| block.transform_values { |parts| parts.map(&:strip).join("\n").strip } }
  end

  # The last label of the last block is the value being read; a boundary
  # closes it by opening a new (empty) block.
  def read_line(blocks, line, next_line)
    label = label_match(line)

    if boundary?(line, next_line)
      blocks << {} if blocks.last.any?
    elsif label
      blocks << {} if blocks.last.key?(label.first)
      blocks.last[label.first] = [label.last]
    elsif blocks.last.any?
      blocks.last.values.last << line
    end
  end

  def boundary?(line, next_line)
    return true if line.lstrip.start_with?('>')

    normalized = normalize(line)
    return true if delimiters.include?(normalized.delete(' '))

    return true if normalized.match?(QUOTE_HEADER)

    # A long "Em … escreveu:" header wrapped over two lines.
    next_normalized = normalize(next_line.to_s)
    !next_normalized.match?(QUOTE_HEADER) && "#{normalized} #{next_normalized}".match?(QUOTE_HEADER)
  end

  def label_match(line)
    label, separator, value = line.sub(LEADING_MARKERS, '').partition(':')
    return if separator.empty?

    key = labels[normalize(label)]
    [key, value.gsub(/\A[*_\s]+|[*_\s]+\z/, '')] if key
  end

  def parse_amount(value)
    match = VALUE_FORMAT.match(value)
    return unless match

    amount = BigDecimal(match[1].delete('.').tr(',', '.'))
    amount if amount.positive?
  end

  def normalize(value)
    I18n.transliterate(value).downcase.delete('*_').sub(LEADING_MARKERS, '').gsub(%r{\s*/\s*}, '/').squish
  end

  def labels
    @labels ||= I18n.t('scan_solo.quote.block.labels').to_h { |key, label| [normalize(label), key] }
  end

  def delimiters
    @delimiters ||= [I18n.t('scan_solo.quote.block.start'), I18n.t('scan_solo.quote.block.end')].map { |label| normalize(label).delete(' ') }
  end

  def html_to_text(html)
    Nokogiri::HTML.fragment(html.gsub(HTML_LINE_BREAKS) { |tag| "#{tag}\n" }).text
  end
end
