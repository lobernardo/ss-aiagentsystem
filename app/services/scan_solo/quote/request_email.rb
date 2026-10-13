# CT-01 / CT-03 / RF-01..RF-13 / RF-16 / RF-17: the quote request e-mail
# (template `quote_request_email.v2`) and its update e-mail, rendered from a
# RequestEmail::Snapshot. Pure: no writes, no HTTP, no language model (RNF-01); the same
# snapshot always renders the same subject, text and HTML.
#
# - Subject (RF-02): RequestEmail::Subject.
# - Body (RF-05..RF-13): the CT-01 sections; optional lines without value are
#   omitted, lead values are quoted as is (`inferido` → "(a confirmar)") and
#   the e-mail ends with the unchanged CT-04 instructions and empty block.
#   A `nao_informado` field (proposta-template-local RF-31 a) always shows
#   "<label>: Não informado pelo cliente", optional lines included, with the
#   snapshot `not_informed` label and never the lead's words.
# - Attachments (RF-13): RequestEmail::Documents; `attachment_ids` narrows
#   the candidates (the update e-mail only attaches new files).
# - RF-11: every body line goes through RequestEmail::BlockGuard.
# - HTML (RF-16, RF-17): every line escaped and joined with `<br>`; the only
#   `href`s are the RF-10 map links and the ScanSOLO conversation link.
# - Update (CT-03, RF-14): `Atualização:`, one line per rendered change, a
#   blank line, the full CT-01 summary and the block.
class ScanSolo::Quote::RequestEmail
  TEMPLATE_VERSION = 'quote_request_email.v2'.freeze
  SERVICE_KEYS = %w[tipo_servico tecnologia interferencias_buscadas].freeze
  TECHNICAL = { 'area' => 'area', 'profundidade' => 'depth', 'prazo_desejado' => 'deadline', 'integracao_seguranca' => 'safety' }.freeze
  CATALOG_LABELS = ScanSolo::Qualification::FieldResolver::CATALOG.to_h { |field| [field[:key], field[:label]] }.freeze

  Result = Struct.new(:email, :attachment_ids, keyword_init: true)

  def self.render(snapshot:, attachment_ids: nil)
    email = new(snapshot, attachment_ids)
    lines = [t('greeting'), '', t('intro'), *(t('validation_mode') if snapshot['validation_mode']), t('data_intro'), '', *email.summary_lines]

    Result.new(email: email.build(email.subject, lines), attachment_ids: email.documents.attached_ids)
  end

  def self.render_update(snapshot:, previous:)
    email = new(snapshot, snapshot['attachments'].pluck('id') - previous['attachments'].pluck('id'))
    lines = [t('update.header'), *email.change_lines(new(previous)), '', *email.summary_lines]

    Result.new(email: email.build(nil, lines), attachment_ids: email.documents.attached_ids)
  end

  def self.changed?(snapshot, previous)
    new(snapshot).change_lines(new(previous)).any?
  end

  def self.t(key, **)
    I18n.t("scan_solo.quote.request_email.#{key}", **)
  end

  def initialize(snapshot, attachment_ids = nil)
    @snapshot = snapshot
    @attachment_ids = attachment_ids
    @fields = snapshot['fields']
  end

  def subject
    ScanSolo::Quote::RequestEmail::Subject.call(
      company: field_value('empresa'), contact_name: snapshot['contact_name'], service_label: service.label, city_uf: field_value('cidade_uf')
    )
  end

  # CT-01 from DADOS DO CLIENTE to the signature; a section without lines is omitted.
  def summary_lines
    sections.flat_map { |key, lines| lines.any? ? [t("sections.#{key}"), *lines, ''] : [] } + closing_lines
  end

  def documents
    @documents ||= ScanSolo::Quote::RequestEmail::Documents.call(
      attachments: snapshot['attachments'], candidate_ids: @attachment_ids, conversation_url: snapshot['conversation_url']
    )
  end

  # CT-03: every rendered value that differs from `previous`, then the new attachments.
  def change_lines(previous)
    before = previous.rendered_values
    after = rendered_values
    changed = (after.keys | before.keys).reject { |label| before[label] == after[label] }.map do |label|
      t('update.change', label: label, previous: before[label] || t('not_informed'), current: after[label] || t('not_informed'))
    end
    changed + new_attachment_lines(previous)
  end

  # RF-17: every line HTML-escaped and joined with `<br>`.
  def build(subject, lines)
    body = lines.flat_map { |line| line.split(/\r?\n/, -1).presence || [''] }.map { |line| ScanSolo::Quote::RequestEmail::BlockGuard.call(line) }
    lines = body + ['', *ScanSolo::Quote::EmailComposer.instruction_lines]

    ScanSolo::Quote::EmailComposer::Email.new(
      subject: subject, text: lines.join("\n"), html: lines.map { |line| linkify(ERB::Util.html_escape(line)) }.join('<br>')
    )
  end

  protected

  attr_reader :snapshot

  def rendered_values
    [client_pairs, location_pairs, service_pairs, [[CATALOG_LABELS['tipo_intervencao'], objective]], technical_pairs, other_pairs,
     [[t('sections.pending'), pending_items.join('; ').presence]]].flatten(1).to_h { |label, text| [label, text] }
  end

  private

  attr_reader :fields

  def sections
    {
      'client' => pair_lines(client_pairs), 'location' => pair_lines(location_pairs),
      'service' => [*(t('service_not_informed') unless service.informed), *pair_lines(service_pairs)], 'objective' => [objective],
      'technical' => pair_lines(technical_pairs), 'other' => pair_lines(other_pairs), 'documents' => documents.lines,
      'pending' => pending_items.map { |item| "* #{item};" }
    }
  end

  def new_attachment_lines(previous)
    sent_ids = previous.snapshot['attachments'].pluck('id')
    snapshot['attachments'].reject { |attachment| sent_ids.include?(attachment['id']) }
                           .map { |attachment| t('update.new_attachment', name: attachment['name'], type: attachment['type']) }
  end

  # Each pair is `[label, text, field key]`; the key only drives the RF-31 (a) label.
  def client_pairs
    [
      [t('labels.company'), value('empresa') || t('not_informed'), 'empresa'], [t('labels.cnpj'), value('cnpj'), 'cnpj'],
      [t('labels.contact'), value('nome'), 'nome'], [t('labels.email'), value('email') || t('not_informed'), 'email'],
      [t('labels.phone'), snapshot['phone'] || t('not_informed')]
    ]
  end

  def location_pairs
    [
      [t('labels.unit'), value('cliente_final'), 'cliente_final'], [t('labels.address'), address || value('endereco_obra') || t('not_informed')],
      [t('labels.city_state'), value('cidade_uf'), 'cidade_uf'], [t('labels.location'), location]
    ]
  end

  def service_pairs
    SERVICE_KEYS.map { |key| [CATALOG_LABELS[key], value(key), key] }
  end

  def technical_pairs
    TECHNICAL.map { |key, label| [t("labels.#{label}"), value(key), key] }
  end

  def other_pairs
    ScanSolo::Quote::RequestEmail::Snapshot::OTHER_KEYS.map { |key| [CATALOG_LABELS[key], value(key), key] }
  end

  def not_informed_labels
    @not_informed_labels ||= snapshot.fetch('not_informed', []).to_h { |entry| entry.values_at('key', 'label') }
  end

  def closing_lines
    [
      t(pending_items.any? ? 'closing_with_pending' : 'closing_without_pending'), '',
      "#{t('conversation_link')}: #{snapshot['conversation_url']}", '', t('sign_off'), t('signature')
    ]
  end

  def pair_lines(pairs)
    pairs.filter_map { |label, text, key| "#{not_informed_labels.fetch(key, label)}: #{text}" if text }
  end

  def objective
    value('tipo_intervencao') || t('not_informed')
  end

  # CT-02: `bairro` goes at the end when the address does not mention it.
  def address
    street = field_value('endereco_obra')
    district = field_value('bairro')
    district = nil if district && street && fold(street).include?(fold(district))
    [(value('endereco_obra') if street), (value('bairro') if district)].compact.join(', ').presence
  end

  def location_links
    @location_links ||= ScanSolo::Quote::RequestEmail::LocationLinks.call(sources: snapshot['location_sources'])
  end

  def location
    return location_links.first if location_links.size <= 1

    location_links.each_with_index.map { |link, index| "#{t('point', number: index + 1)}: #{link}" }.join('; ')
  end

  def pending_items
    @pending_items ||= ScanSolo::Quote::RequestEmail::PendingItems.call(
      missing_labels: snapshot['missing_labels'], service: service, values: fields.transform_values { |field| field['value'] },
      attachments: snapshot['attachments'], not_informed: snapshot.fetch('not_informed', [])
    )
  end

  def service
    @service ||= ScanSolo::Quote::RequestEmail::ServiceLabel.call(tipo_servico: field_value('tipo_servico'), tecnologia: field_value('tecnologia'))
  end

  def field_value(key)
    fields.dig(key, 'value').presence
  end

  # RF-06: quoted as is; `inferido` gets "(a confirmar)". RF-31 (a): `nao_informado` gets the fixed text.
  def value(key)
    return t('not_informed_by_client') if fields.dig(key, 'not_informed')

    text = field_value(key)
    return if text.nil?

    fields[key]['inferred'] ? "#{text} #{I18n.t('scan_solo.quote.email.to_confirm')}" : text
  end

  def fold(text)
    I18n.transliterate(text).downcase.squish
  end

  # RF-16: only the map links and the conversation link become clickable.
  def linkify(escaped_line)
    escaped_line.gsub(/\S+/) do |token|
      url = token.end_with?(';') && allowed_links.exclude?(token) ? token.delete_suffix(';') : token
      allowed_links.include?(url) ? %(<a href="#{url}">#{url}</a>#{token.delete_prefix(url)}) : token
    end
  end

  def allowed_links
    @allowed_links ||= [*location_links, snapshot['conversation_url']].map { |link| ERB::Util.html_escape(link).to_s }
  end

  def t(key, **)
    self.class.t(key, **)
  end
end
