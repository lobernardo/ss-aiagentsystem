# RF-11: keeps lead text from being read as the CT-04 reply block. A line
# that ResponseBlockParser would take as a block label (`Valor total:` …) or
# delimiter gets the neutral prefix `» `; the text itself is kept. The `- `
# of the SPEC is stripped by the parser (LEADING_MARKERS), so it would not
# neutralize the line (PLAN Q1). Same normalization as the parser.
class ScanSolo::Quote::RequestEmail::BlockGuard
  PREFIX = '» '.freeze
  LEADING_MARKERS = ScanSolo::Quote::ResponseBlockParser::LEADING_MARKERS

  def self.call(line)
    label, separator, = line.sub(LEADING_MARKERS, '').partition(':')
    imitates_block = (separator.present? && labels.include?(normalize(label))) || delimiters.include?(normalize(line).delete(' '))
    imitates_block ? "#{PREFIX}#{line}" : line
  end

  def self.normalize(text)
    I18n.transliterate(text).downcase.delete('*_').sub(LEADING_MARKERS, '').gsub(%r{\s*/\s*}, '/').squish
  end

  def self.labels
    I18n.t('scan_solo.quote.block.labels').values.map { |label| normalize(label) }
  end

  def self.delimiters
    %w[start end].map { |key| normalize(I18n.t("scan_solo.quote.block.#{key}")).delete(' ') }
  end

  private_class_method :normalize, :labels, :delimiters
end
