# RF-08 / CT-07: the "INFORMAÇÕES AINDA NÃO CONFIRMADAS" list of the quote
# request e-mail, by fixed rule (no LLM, no I/O). The CT-07 items configured
# for the service (`Settings.pending_indexes`) whose "informed" condition fails
# come first, in CT-07 order; then the config `missing_labels` (config order),
# plus the catalog label `Tipo de serviço` when no service was informed
# (RF-04). No label is repeated.
#
# `values` maps catalog keys to their rendered value; `attachments` are the
# lead attachments (`name`, `file_type`) of the snapshot.
class ScanSolo::Quote::RequestEmail::PendingItems
  INFORMED_WHEN = {
    1 => ->(values, _attachments) { values['area'].present? || values['metragem'].present? },
    2 => ->(values, _attachments) { values['profundidade'].present? },
    3 => ->(values, _attachments) { values['integracao_seguranca'].present? },
    4 => ->(values, _attachments) { values['restricoes_acesso'].present? || values['documentacoes_necessarias'].present? },
    5 => ->(values, _attachments) { values['prazo_desejado'].present? || values['data_desejada'].present? },
    6 => ->(_values, attachments) { attachments.any? { |attachment| attachment['file_type'] == 'image' } },
    7 => ->(_values, attachments) { attachments.any? { |attachment| attachment['name'].to_s.downcase.end_with?('.kmz', '.kml') } },
    8 => ->(values, _attachments) { values['condicoes_especiais'].present? }
  }.freeze
  SERVICE_TYPE_LABEL = ScanSolo::Qualification::FieldResolver::CATALOG.find { |field| field[:key] == 'tipo_servico' }.fetch(:label)

  def self.call(missing_labels:, service:, values:, attachments:)
    indexes = ScanSolo::Quote::RequestEmail::Settings.load.pending_indexes(service.service_key).sort
    fixed = indexes.reject { |index| INFORMED_WHEN.fetch(index).call(values, attachments) }
                   .map { |index| I18n.t("scan_solo.quote.request_email.pending_items.#{index}") }
    required = missing_labels + (service.informed ? [] : [SERVICE_TYPE_LABEL])

    (fixed + required).uniq
  end
end
