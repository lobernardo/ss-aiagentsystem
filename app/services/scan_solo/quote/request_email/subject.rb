# RF-02 / RF-03 / RF-17 / RNF-02: the quote request subject
# `Solicitação de orçamento | {empresa_curta} | {servico_label}[ | {cidade}/{uf}]`.
# The city part only appears when `cidade_uf` ends in one of the 27 UF codes,
# separated by `/`, `-`, `,` or a space. Control characters become spaces
# (no header injection). Above 120 characters the company is truncated first
# (down to 1 character + `…`), then the remaining parts from the end. Pure.
class ScanSolo::Quote::RequestEmail::Subject
  MAX_LENGTH = 120
  UF = %w[AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO].freeze
  CITY_UF = %r{\A(?<city>.+?)(?:\s*[/,-]\s*|\s+)(?<uf>[[:alpha:]]{2})\z}
  SEPARATOR = ' | '.freeze
  ELLIPSIS = '…'.freeze

  def self.call(company:, contact_name:, service_label:, city_uf:)
    short = clean(ScanSolo::Quote::RequestEmail::CompanyShortName.call(company: clean(company), contact_name: clean(contact_name)))
    parts = [short.presence || I18n.t('scan_solo.quote.request_email.not_informed'), clean(service_label), *city_part(clean(city_uf))]

    [0, *(parts.size - 1).downto(1)].each do |index|
      excess = join(parts).length - MAX_LENGTH
      break unless excess.positive?

      parts[index] = truncate(parts[index], parts[index].length - excess)
    end
    join(parts)
  end

  def self.city_part(city_uf)
    match = city_uf.match(CITY_UF)
    uf = match && match[:uf].upcase
    "#{match[:city].squish}/#{uf}" if UF.include?(uf)
  end

  def self.join(parts)
    [I18n.t('scan_solo.quote.request_email.subject_prefix'), *parts].join(SEPARATOR)
  end

  def self.truncate(text, length)
    length = [length, ELLIPSIS.length + 1].max
    text.length <= length ? text : "#{text[0, length - ELLIPSIS.length].rstrip}#{ELLIPSIS}"
  end

  def self.clean(text)
    text.to_s.gsub(/[[:cntrl:]]/, ' ').squish
  end

  private_class_method :city_part, :join, :truncate, :clean
end
