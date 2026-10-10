# RF-04: `{servico_label}` of the quote request e-mail, from `tipo_servico` and
# `tecnologia` (case and accents ignored) and the term map of the versioned
# settings file (RF-21). Terms of both groups → the combined label; no known
# term → the free text of `tipo_servico` (else `tecnologia`) with only the
# RF-02(b) treatment and `service_key` `outro`; both empty → the i18n
# "Serviço não informado" with `informed: false`. The label is never empty.
class ScanSolo::Quote::RequestEmail::ServiceLabel
  OTHER_KEY = 'outro'.freeze
  CONTROL_CHARS = /[[:cntrl:]]/

  Result = Struct.new(:label, :service_key, :informed, keyword_init: true)

  def self.call(tipo_servico:, tecnologia:)
    free_text = [tipo_servico, tecnologia].map { |value| value.to_s.gsub(CONTROL_CHARS, ' ').squish }
    if free_text.all?(&:empty?)
      return Result.new(label: I18n.t('scan_solo.quote.request_email.service_not_informed'), service_key: OTHER_KEY, informed: false)
    end

    label = recognized_label(I18n.transliterate(free_text.join(' ')).downcase)
    Result.new(label: label || free_text.find(&:present?), service_key: label || OTHER_KEY, informed: true)
  end

  def self.recognized_label(text)
    settings = ScanSolo::Quote::RequestEmail::Settings.load
    matched = settings.service_labels.select { |entry| entry.terms.any? { |term| text.include?(I18n.transliterate(term).downcase) } }
    matched.size > 1 ? settings.combined_label : matched.first&.label
  end
  private_class_method :recognized_label
end
