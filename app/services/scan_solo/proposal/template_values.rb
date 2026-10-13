# CT-03 / RF-05 / RF-07 / RF-24 / RF-33 (e): the 16 values of the proposal
# template, keyed by TemplateDocument::PLACEHOLDERS. Pure and deterministic:
# 0 writes, 0 HTTP, 0 LLM; nothing is calculated, adjusted or completed.
#
# - Dates: pt-BR long form in Cadence::SendingWindow::ZONE, months from
#   `scan_solo.proposal.months`.
# - Qualification: the lead state value when `confirmado`/`inferido`, then
#   FieldResolver.contact_value (native column → `custom_attributes`). A
#   `nao_informado` key is absent without reading the contact, whose mirror
#   may hold the lead's own words. A missing value becomes the neutral text
#   and never fails the generation (the proposal gate is not consulted).
# - Value, schedule, scope, payment terms and notes: only `commercial`.
class ScanSolo::Proposal::TemplateValues
  STATE_VALUE_STATUSES = %w[confirmado inferido].freeze
  CITY_SEPARATOR = ' – '.freeze

  def self.call(proposal_version:, generated_at:)
    new(proposal_version: proposal_version, generated_at: generated_at).call
  end

  def initialize(proposal_version:, generated_at:)
    @proposal_version = proposal_version
    @generated_at = generated_at
    @quote_request = proposal_version.quote_request
    @opportunity = quote_request.opportunity
  end

  def call
    {
      'NUMERO_PROPOSTA' => proposal_version.proposal_number,
      'DATA_PROPOSTA' => long_date(generated_at),
      # D-01 (provisional): the day the quote request was sent to the commercial team.
      'DATA_SOLICITACAO' => long_date(quote_request.created_at),
      'NOME_EMPRESA' => first_qualification('empresa', 'nome') || not_informed,
      'NOME_CONTATO' => first_qualification('nome') || not_informed,
      'PROJETO_CLIENTE_FINAL' => first_qualification('cliente_final', 'empresa', 'nome') || not_informed,
      'ENDERECO_OBRA' => address || not_informed,
      'CIDADE_ESTADO' => city || not_informed,
      'RUA_CIDADE_ESTADO' => street_city,
      'TRECHO_PROFUNDIDADE' => depth_excerpt,
      **commercial_values
    }
  end

  private

  attr_reader :proposal_version, :generated_at, :quote_request, :opportunity

  def commercial_values
    commercial = quote_request.commercial
    amount = BigDecimal(commercial['total_value'].to_s)
    {
      'DESCRICAO_ESCOPO' => commercial['scope'].to_s,
      'PRAZO_CRONOGRAMA' => commercial['schedule'].to_s,
      'CONDICOES_PAGAMENTO' => commercial['payment_terms'].to_s,
      'OBSERVACOES_COMERCIAIS' => commercial['notes'].to_s,
      'VALOR_NUMERICO' => ActiveSupport::NumberHelper.number_to_rounded(amount, precision: 2, delimiter: '.', separator: ','),
      'VALOR_EXTENSO' => ScanSolo::Quote::AmountInWords.call(amount)
    }
  end

  def first_qualification(*keys)
    keys.lazy.filter_map { |key| qualification(key) }.first
  end

  def qualification(key)
    entry = state_fields[key]
    return if entry&.dig('status') == 'nao_informado'

    value = entry['value'] if STATE_VALUE_STATUSES.include?(entry&.dig('status'))
    value = ScanSolo::Qualification::FieldResolver.contact_value(contact: opportunity.contact, canonical_key: key) if value.blank?
    value.to_s.strip.presence
  end

  def state_fields
    @state_fields ||= opportunity.lead_state.fields
  end

  # `bairro` alone is not an address.
  def address
    street = qualification('endereco_obra')
    ScanSolo::Quote::RequestEmail.address_with_district(street, qualification('bairro')) if street
  end

  # `Cidade – UF` when the value ends in a valid UF (SO/RF-02 a), else as is.
  def city
    value = qualification('cidade_uf')
    match = value&.match(ScanSolo::Quote::RequestEmail::Subject::CITY_UF)
    uf = match && match[:uf].upcase
    ScanSolo::Quote::RequestEmail::Subject::UF.include?(uf) ? "#{match[:city].squish}#{CITY_SEPARATOR}#{uf}" : value
  end

  def street_city
    return t('address_in_city', address: address, city: city) if address && city

    address || city || t('location_not_informed')
  end

  def depth_excerpt
    depth = first_qualification('profundidade', 'profundidade_intervencao')
    depth ? t('depth_excerpt', value: depth) : ''
  end

  def long_date(time)
    date = time.in_time_zone(ScanSolo::Cadence::SendingWindow::ZONE).to_date
    t('long_date', day: date.day, month: t('months')[date.month - 1], year: date.year)
  end

  def not_informed
    t('not_informed')
  end

  def t(key, **)
    I18n.t("scan_solo.proposal.#{key}", **)
  end
end
