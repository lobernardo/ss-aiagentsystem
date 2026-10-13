# RF-08 / CT-07: the "INFORMAÇÕES AINDA NÃO CONFIRMADAS" list of the quote
# request e-mail, by fixed rule (no language model, no I/O). The CT-07 items configured
# for the service (`Settings.pending_indexes`) whose "informed" condition fails
# come first, in CT-07 order; then the config `missing_labels` (config order),
# plus the catalog label `Tipo de serviço` when no service was informed
# (RF-04). No label is repeated.
#
# proposta-template-local RF-31 (b, c): a fixed item that fails only because
# of `nao_informado` fields (it would pass counting them as present) stays
# listed with the " (cliente não soube informar)" suffix and covers those
# fields; every other `nao_informado` field comes after the fixed items as
# "<label> (cliente não soube informar)".
#
# `values` maps catalog keys to their rendered value; `not_informed` is the
# snapshot list of `nao_informado` fields (`key`, `label`); `attachments` are
# the lead attachments (`name`, `file_type`) of the snapshot.
class ScanSolo::Quote::RequestEmail::PendingItems
  ITEM_FIELDS = {
    1 => %w[area metragem], 2 => %w[profundidade], 3 => %w[integracao_seguranca], 4 => %w[restricoes_acesso documentacoes_necessarias],
    5 => %w[prazo_desejado data_desejada], 8 => %w[condicoes_especiais]
  }.freeze
  INFORMED_WHEN = ITEM_FIELDS.transform_values { |keys| ->(values, _attachments) { values.values_at(*keys).any?(&:present?) } }.merge(
    6 => ->(_values, attachments) { attachments.any? { |attachment| attachment['file_type'] == 'image' } },
    7 => ->(_values, attachments) { attachments.any? { |attachment| attachment['name'].to_s.downcase.end_with?('.kmz', '.kml') } }
  ).freeze
  SERVICE_TYPE_LABEL = ScanSolo::Qualification::FieldResolver::CATALOG.find { |field| field[:key] == 'tipo_servico' }.fetch(:label)

  def self.call(missing_labels:, service:, values:, attachments:, not_informed: [])
    new(values: values, attachments: attachments, not_informed: not_informed).call(missing_labels: missing_labels, service: service)
  end

  def initialize(values:, attachments:, not_informed:)
    @values = values
    @attachments = attachments
    @not_informed = not_informed
  end

  def call(missing_labels:, service:)
    failing = ScanSolo::Quote::RequestEmail::Settings.load.pending_indexes(service.service_key).sort
                                                     .reject { |index| informed?(index, values) }
    covered = failing.select { |index| informed?(index, answered_values) }
    fixed = failing.map { |index| "#{fixed_label(index)}#{suffix if covered.include?(index)}" }
    required = missing_labels + (service.informed ? [] : [SERVICE_TYPE_LABEL])

    (fixed + required + unanswered_labels(covered.flat_map { |index| ITEM_FIELDS.fetch(index) })).uniq
  end

  private

  attr_reader :values, :attachments, :not_informed

  def informed?(index, item_values)
    INFORMED_WHEN.fetch(index).call(item_values, attachments)
  end

  # Values with every `nao_informado` key counted as present.
  def answered_values
    @answered_values ||= values.merge(not_informed.pluck('key').index_with(true))
  end

  def fixed_label(index)
    I18n.t("scan_solo.quote.request_email.pending_items.#{index}")
  end

  def unanswered_labels(covered_keys)
    not_informed.reject { |entry| covered_keys.include?(entry['key']) }.map { |entry| "#{entry['label']}#{suffix}" }
  end

  def suffix
    I18n.t('scan_solo.quote.request_email.not_informed_suffix')
  end
end
