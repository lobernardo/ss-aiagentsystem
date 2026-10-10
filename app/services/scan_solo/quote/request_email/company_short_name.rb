# RF-03: `{empresa_curta}` of the quote request subject, derived from the
# company name (razão social) by a local rule only -- no external source, no I/O.
# Corporate and activity suffixes, plus the punctuation and spaces left over,
# are removed from the end repeatedly, ignoring case and accents. A result
# shorter than 2 characters is ambiguous and keeps the full company name;
# without a company, the contact name is used.
class ScanSolo::Quote::RequestEmail::CompanyShortName
  SUFFIXES = [
    'Exportação e Importação', 'Importação e Exportação', 'Comércio', 'Indústria',
    'EIRELI', 'Ltda.', 'Ltda', 'S.A.', 'S/A', 'SA', 'EPP', 'MEI', 'ME'
  ].freeze
  MIN_LENGTH = 2
  TRAILING_JUNK = /[\s[:punct:]]+\z/

  # Folds case and accents character by character, so the folded string keeps
  # the length of the original and a suffix match can be cut from it.
  def self.fold(text)
    text.unicode_normalize(:nfc).each_char.map { |char| char.unicode_normalize(:nfd)[0].downcase }.join
  end

  FOLDED_SUFFIXES = SUFFIXES.map { |suffix| fold(suffix) }.sort_by { |suffix| -suffix.length }.freeze

  def self.call(company:, contact_name:)
    company = company.to_s.strip
    return contact_name if company.empty?

    short = company.unicode_normalize(:nfc)
    loop do
      folded = fold(short)
      suffix = FOLDED_SUFFIXES.find do |candidate|
        folded.end_with?(candidate) && !folded[-candidate.length - 1].to_s.match?(/[[:alnum:]]/)
      end
      if suffix
        short = short[0...-suffix.length]
      elsif short.match?(TRAILING_JUNK)
        short = short.sub(TRAILING_JUNK, '')
      else
        break
      end
    end

    short.length < MIN_LENGTH ? company : short
  end
end
