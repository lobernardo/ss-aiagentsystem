# RF-01..RF-06, RF-21: the single reader of the "qualification field
# satisfied?" rule. For each entry of the published
# `required_qualification_fields` (in config order) it reports the config
# label, its canonical key, the current value, the origin (`native` |
# `custom_attribute`) and whether it is satisfied.
#
# Labels and `custom_attributes` keys are compared by their normalized form
# (trim, case, accents and `_ - space /` separators ignored) and mapped
# through the frozen canonical alias table; a label with no alias uses its
# normalized form as canonical key. `nome`/`email`/`telefone` read the native
# contact column first and fall back to `custom_attributes` when it is blank.
#
# Deterministic by design: only the config, the contact's native fields and
# `custom_attributes` are read -- never messages, an LLM or HTTP -- and
# nothing is written.
class ScanSolo::Qualification::FieldResolver
  # RF-04, in table order (the order is the RF-21 alias read precedence).
  # The canonical key itself is also an accepted spelling of its entry.
  ALIASES = {
    'nome' => ['Nome', 'nome completo', 'name'],
    'telefone' => %w[Telefone WhatsApp],
    'email' => %w[E-mail email],
    'tipo_intervencao' => ['Objetivo do serviço', 'tipo de intervenção', 'escopo'],
    'cidade_uf' => ['Cidade / UF', 'cidade'],
    'endereco_obra' => ['Endereço da obra', 'endereço'],
    'area' => ['Área ou extensão', 'área', 'area_total'],
    'profundidade' => ['Profundidade de interesse', 'profundidade'],
    'prazo_desejado' => ['Prazo desejado', 'prazo', 'urgência'],
    'empresa' => ['Empresa', 'razão social', 'company'],
    'integracao_seguranca' => ['Integração de segurança']
  }.freeze

  NATIVE = { 'nome' => :name, 'email' => :email, 'telefone' => :phone_number }.freeze

  # RF-15: the fixed canonical key set of the Make `qualification` object.
  MAKE_KEYS = %w[empresa endereco_obra cidade_uf tipo_intervencao area profundidade prazo_desejado email nome telefone].freeze

  Field = Struct.new(:label, :canonical_key, :value, :origin, :satisfied, keyword_init: true) do
    def satisfied?
      satisfied
    end
  end

  def self.normalize(key)
    I18n.transliterate(key.to_s.strip).downcase.split(%r{[\s_/-]+}).compact_blank.join('_')
  end

  # Normalized spellings per canonical key, in alias-table order.
  SPELLINGS = ALIASES.to_h { |canonical, spellings| [canonical, [*spellings, canonical].map { |spelling| normalize(spelling) }.uniq] }.freeze
  CANONICAL_BY_SPELLING = SPELLINGS.flat_map { |canonical, spellings| spellings.map { |spelling| [spelling, canonical] } }.to_h.freeze

  def self.canonical_key(key)
    normalized = normalize(key)
    CANONICAL_BY_SPELLING.fetch(normalized, normalized)
  end

  def self.call(contact:, config:)
    new(contact: contact, config: config)
  end

  def initialize(contact:, config:)
    @contact = contact
    @labels = Array(config&.required_qualification_fields)
  end

  def fields
    @fields ||= labels.map do |label|
      canonical = self.class.canonical_key(label)
      value, origin = resolve(canonical, label)
      Field.new(label: label, canonical_key: canonical, value: value, origin: origin, satisfied: origin.present?)
    end
  end

  def missing_labels
    fields.reject(&:satisfied?).map(&:label)
  end

  def collected
    fields.select(&:satisfied?).to_h { |field| [field.label, field.value] }
  end

  def required_canonical_keys
    fields.map(&:canonical_key)
  end

  # RF-15: all 10 canonical keys are evaluated whether or not the config
  # requires them; only present values are sent.
  def make_qualification
    MAKE_KEYS.each_with_object({}) do |canonical, qualification|
      label = fields.find { |field| field.canonical_key == canonical }&.label
      value, = resolve(canonical, label)
      qualification[canonical] = value if value.present?
    end
  end

  private

  attr_reader :contact, :labels

  def resolve(canonical, label)
    return [nil, nil] if contact.blank?

    native = NATIVE[canonical] && contact.public_send(NATIVE[canonical])
    return [native, 'native'] if native.present?

    key = custom_attribute_key(canonical, label)
    key ? [contact.custom_attributes[key], 'custom_attribute'] : [nil, nil]
  end

  def custom_attribute_key(canonical, label)
    contact.custom_attributes
           .select { |key, value| value.present? && self.class.canonical_key(key) == canonical }
           .keys.min_by { |key| precedence(key, canonical, label) }
  end

  # RF-21: exact canonical key > exact config label > alias-table order >
  # lexicographic.
  def precedence(key, canonical, label)
    spellings = SPELLINGS.fetch(canonical, [])
    rank = if key == canonical
             0
           elsif key == label
             1
           else
             2 + (spellings.index(self.class.normalize(key)) || spellings.size)
           end
    [rank, key]
  end
end
