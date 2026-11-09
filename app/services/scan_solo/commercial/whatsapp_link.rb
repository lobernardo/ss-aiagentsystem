# Escalação comercial RF-05/CT-05: the application-built wa.me link to the
# public commercial contact (Artur), from the published number only. The
# model writes PLACEHOLDER and never a URL or phone. The prefilled text names
# Artur plus the lead's name, company, service and proposal number, each line
# only when known (a `faltante`/`nao_informado` field is unknown, the same
# rule as the opportunity JSON). Pure: reads the opportunity, no HTTP, no LLM.
module ScanSolo::Commercial::WhatsappLink
  PLACEHOLDER = '{{LINK_ARTUR}}'.freeze
  UNKNOWN_STATUSES = %w[faltante nao_informado].freeze

  def self.build(config:, opportunity:)
    number = config.commercial_whatsapp_number
    return if number.blank?

    "https://wa.me/#{number.delete('+')}?text=#{ERB::Util.url_encode(text(opportunity))}"
  end

  def self.text(opportunity)
    fields = opportunity.lead_state&.fields.to_h
    values = {
      name: field_value(fields, 'nome') || opportunity.contact.name.presence,
      company: field_value(fields, 'empresa'),
      service: field_value(fields, 'tipo_servico'),
      proposal: opportunity.proposal&.current_version&.proposal_number
    }
    lines = values.filter_map { |key, value| I18n.t("scan_solo.commercial.whatsapp_text.#{key}", value: value) if value.present? }

    [I18n.t('scan_solo.commercial.whatsapp_text.greeting'), *lines].join("\n")
  end

  def self.field_value(fields, key)
    field = fields[key].to_h
    field['value'].presence unless UNKNOWN_STATUSES.include?(field['status'])
  end
  private_class_method :text, :field_value
end
