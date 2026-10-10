# RF-01 / RF-05..RF-07 / RF-10 / RF-13 / RF-14 / CT-02 / RNF-01: the single
# database read of the quote request e-mail. Returns a canonical Hash (string
# keys, fixed order, JSON types only) that feeds the renderer and is the
# "qualification version" compared by the update e-mail (RF-14).
#
# - `fields`: each CT-02 catalog key as `{ value, inferred }`, by the
#   FieldResolver precedence (lead state non-`faltante` → native contact
#   column → `custom_attributes`). The lead state `telefone` is never read:
#   `phone` is only `contact.phone_number` (RF-07).
# - `location_sources`: the lead state `link_local`, the `location`
#   attachments and the map URLs of the `incoming` messages of the
#   opportunity's WhatsApp conversation, in order of receipt (RF-10).
# - `attachments`: the `image`/`audio`/`video`/`file` attachments of those
#   messages, in order of receipt (RF-13). Nothing is downloaded.
# Read only: no writes, no HTTP, no LLM.
class ScanSolo::Quote::RequestEmail::Snapshot
  OTHER_KEYS = %w[
    cargo emails_copia metragem quantidade_pontos profundidade_intervencao superficie observacoes_tecnicas data_desejada diarias
    tempo_integracao restricoes_acesso documentacoes_necessarias prazo_proposta email_envio_proposta emails_copia_proposta condicoes_especiais
  ].freeze
  FIELD_KEYS = (%w[
    empresa cnpj nome email cliente_final endereco_obra bairro cidade_uf tipo_servico tecnologia interferencias_buscadas tipo_intervencao
    area profundidade prazo_desejado integracao_seguranca
  ] + OTHER_KEYS).freeze
  FILE_TYPES = %w[image audio video file].freeze

  def self.call(opportunity:, config:)
    new(opportunity: opportunity, config: config).call
  end

  def initialize(opportunity:, config:)
    @opportunity = opportunity
    @config = config
    @contact = opportunity.contact
    @state_fields = opportunity.lead_state.fields
    @conversation = opportunity.conversation
  end

  def call
    {
      'fields' => FIELD_KEYS.index_with { |key| field(key) },
      'contact_name' => contact.name.to_s.strip.presence,
      'phone' => contact.phone_number.presence,
      'missing_labels' => ScanSolo::Qualification::FieldResolver.call(opportunity: opportunity, config: config).missing_labels,
      'validation_mode' => config.quote_email_validation_mode,
      'conversation_url' => ScanSolo::Quote::EmailComposer.conversation_url(conversation.account_id, conversation.display_id),
      'location_sources' => location_sources,
      'attachments' => attachments
    }
  end

  private

  attr_reader :opportunity, :config, :contact, :state_fields, :conversation

  def field(key)
    entry = state_fields[key]
    if entry && entry['status'] != 'faltante'
      { 'value' => entry['value'].to_s.strip.presence, 'inferred' => entry['status'] == 'inferido' }
    else
      value = ScanSolo::Qualification::FieldResolver.contact_value(contact: contact, canonical_key: key)
      { 'value' => value.to_s.strip.presence, 'inferred' => false }
    end
  end

  def incoming_messages
    @incoming_messages ||= conversation.messages.incoming.includes(attachments: { file_attachment: :blob }).order(:created_at, :id).to_a
  end

  # [received at, id, url] candidates sorted chronologically; the lead state
  # link sorts by the time it was written.
  def location_sources
    candidates = incoming_messages.flat_map { |message| message_locations(message).map { |url| [message.created_at, message.id, url] } }
    link = state_fields['link_local']
    candidates << [Time.zone.parse(link['updated_at']), 0, link['value']] if link && link['status'] != 'faltante'

    candidates.each_with_index.sort_by { |(at, id, _url), index| [at, id, index] }.map { |(_at, _id, url), _index| url }
  end

  def message_locations(message)
    reader = ScanSolo::AiTurn::AttachmentReader
    locations = message.attachments.select(&:location?).sort_by(&:id).map { |attachment| reader.location_link(attachment) }
    locations + reader.urls(message.content).grep(reader::MAP_URL_PATTERN)
  end

  def attachments
    incoming_messages.flat_map { |message| message.attachments.sort_by(&:id) }
                     .select { |attachment| FILE_TYPES.include?(attachment.file_type) && attachment.file.attached? }
                     .map do |attachment|
      name = attachment.file.filename.to_s
      extension = File.extname(name).delete_prefix('.').upcase
      { 'id' => attachment.id, 'name' => name, 'type' => extension.presence || attachment.file_type, 'file_type' => attachment.file_type,
        'byte_size' => attachment.file.byte_size }
    end
  end
end
