# RF-01..RF-06, RF-21; lead state RF-04, RF-08, RF-15: the single reader of
# the "qualification field satisfied?" rule. For each entry of the published
# `required_qualification_fields` (in config order) it reports the config
# label, its canonical key, the current value and its origin
# (`lead_state` | `native` | `custom_attribute`), the lead state status and
# whether it is satisfied.
#
# A field is satisfied if and only if its canonical key is `confirmado` in
# the opportunity's lead state; a label outside the RF-02 catalog is never
# satisfied (fail-closed, status `faltante`). The value comes from the lead
# state when it is not `faltante`, then from the native contact column
# (`nome`/`email`/`telefone`), then from `custom_attributes`.
#
# Labels and `custom_attributes` keys are compared by their normalized form
# (trim, case, accents and `_ - space /` separators ignored) and mapped
# through the frozen canonical alias table; a label with no alias uses its
# normalized form as canonical key.
#
# Deterministic by design: only the config, the lead state, the contact's
# native fields and `custom_attributes` are read -- never messages, an LLM or
# HTTP -- and nothing is written.
class ScanSolo::Qualification::FieldResolver
  # Lead state RF-02: closed catalog in qualification question order.
  CATALOG = [
    { key: 'nome', block: 'identificacao', label: 'Contato' },
    { key: 'empresa', block: 'identificacao', label: 'Empresa / razão social' },
    { key: 'cargo', block: 'identificacao', label: 'Cargo' },
    { key: 'cnpj', block: 'identificacao', label: 'CNPJ' },
    { key: 'telefone', block: 'identificacao', label: 'Telefone' },
    { key: 'email', block: 'identificacao', label: 'E-mail principal' },
    { key: 'emails_copia', block: 'identificacao', label: 'E-mails em cópia' },
    { key: 'tipo_servico', block: 'servico', label: 'Tipo de serviço' },
    { key: 'tipo_intervencao', block: 'servico', label: 'Objetivo' },
    { key: 'tecnologia', block: 'servico', label: 'Tecnologia' },
    { key: 'interferencias_buscadas', block: 'servico', label: 'Interferências buscadas' },
    { key: 'cliente_final', block: 'local', label: 'Cliente / local final' },
    { key: 'cidade_uf', block: 'local', label: 'Cidade / UF' },
    { key: 'endereco_obra', block: 'local', label: 'Endereço' },
    { key: 'bairro', block: 'local', label: 'Bairro' },
    { key: 'link_local', block: 'local', label: 'Link' },
    { key: 'area', block: 'escopo', label: 'Área' },
    { key: 'metragem', block: 'escopo', label: 'Metragem' },
    { key: 'quantidade_pontos', block: 'escopo', label: 'Quantidade de pontos' },
    { key: 'profundidade', block: 'escopo', label: 'Profundidade de investigação' },
    { key: 'profundidade_intervencao', block: 'escopo', label: 'Profundidade da intervenção' },
    { key: 'superficie', block: 'escopo', label: 'Superfície' },
    { key: 'observacoes_tecnicas', block: 'escopo', label: 'Observações técnicas' },
    { key: 'data_desejada', block: 'execucao', label: 'Data desejada' },
    { key: 'prazo_desejado', block: 'execucao', label: 'Prazo' },
    { key: 'diarias', block: 'execucao', label: 'Diárias' },
    { key: 'integracao_seguranca', block: 'execucao', label: 'Integração' },
    { key: 'tempo_integracao', block: 'execucao', label: 'Tempo de integração' },
    { key: 'restricoes_acesso', block: 'execucao', label: 'Restrições de acesso' },
    { key: 'documentacoes_necessarias', block: 'execucao', label: 'Documentações necessárias' },
    { key: 'prazo_proposta', block: 'comercial', label: 'Prazo para proposta' },
    { key: 'email_envio_proposta', block: 'comercial', label: 'E-mail para envio' },
    { key: 'emails_copia_proposta', block: 'comercial', label: 'Cópias' },
    { key: 'condicoes_especiais', block: 'comercial', label: 'Condições especiais' }
  ].map(&:freeze).freeze
  CATALOG_KEYS = CATALOG.pluck(:key).freeze
  BLOCKS = CATALOG.pluck(:block).uniq.freeze # rubocop:disable Rails/UniqBeforePluck -- CATALOG is an Array, not a relation

  # RF-04, in table order (the order is the RF-21 alias read precedence).
  # The canonical key itself is also an accepted spelling of its entry.
  ALIASES = {
    'nome' => ['Nome', 'nome completo', 'name', 'Contato'],
    'telefone' => %w[Telefone WhatsApp],
    'email' => ['E-mail', 'email', 'E-mail principal'],
    'tipo_intervencao' => ['Objetivo do serviço', 'tipo de intervenção', 'escopo', 'Objetivo'],
    'cidade_uf' => ['Cidade / UF', 'cidade'],
    'endereco_obra' => ['Endereço da obra', 'endereço'],
    'area' => ['Área ou extensão', 'área', 'area_total'],
    'profundidade' => ['Profundidade de interesse', 'profundidade', 'Profundidade de investigação'],
    'prazo_desejado' => ['Prazo desejado', 'prazo', 'urgência'],
    'empresa' => ['Empresa', 'razão social', 'company', 'Empresa / razão social'],
    'integracao_seguranca' => ['Integração de segurança', 'Integração'],
    'cargo' => ['Cargo'],
    'cnpj' => ['CNPJ'],
    'emails_copia' => ['E-mails em cópia'],
    'tipo_servico' => ['Tipo de serviço'],
    'tecnologia' => ['Tecnologia'],
    'interferencias_buscadas' => ['Interferências buscadas'],
    'cliente_final' => ['Cliente / local final'],
    'bairro' => ['Bairro'],
    'link_local' => ['Link'],
    'metragem' => ['Metragem'],
    'quantidade_pontos' => ['Quantidade de pontos'],
    'profundidade_intervencao' => ['Profundidade da intervenção'],
    'superficie' => ['Superfície'],
    'observacoes_tecnicas' => ['Observações técnicas'],
    'data_desejada' => ['Data desejada'],
    'diarias' => ['Diárias'],
    'tempo_integracao' => ['Tempo de integração'],
    'restricoes_acesso' => ['Restrições de acesso'],
    'documentacoes_necessarias' => ['Documentações necessárias'],
    'prazo_proposta' => ['Prazo para proposta'],
    'email_envio_proposta' => ['E-mail para envio'],
    'emails_copia_proposta' => ['Cópias'],
    'condicoes_especiais' => ['Condições especiais']
  }.freeze

  NATIVE = { 'nome' => :name, 'email' => :email, 'telefone' => :phone_number }.freeze

  # RF-15: the fixed canonical key set of the Make `qualification` object.
  MAKE_KEYS = %w[empresa endereco_obra cidade_uf tipo_intervencao area profundidade prazo_desejado email nome telefone].freeze

  Field = Struct.new(:label, :canonical_key, :value, :origin, :status, :classification, :satisfied, keyword_init: true) do
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

  def self.call(opportunity:, config:)
    new(opportunity: opportunity, config: config)
  end

  # Native column first, then `custom_attributes` by RF-21 precedence.
  def self.contact_value(contact:, canonical_key:)
    contact_resolution(contact, canonical_key, nil).first
  end

  def self.contact_resolution(contact, canonical, label)
    native = NATIVE[canonical] && contact.public_send(NATIVE[canonical])
    return [native, 'native'] if native.present?

    key = contact.custom_attributes
                 .select { |candidate, value| value.present? && canonical_key(candidate) == canonical }
                 .keys.min_by { |candidate| precedence(candidate, canonical, label) }
    key ? [contact.custom_attributes[key], 'custom_attribute'] : [nil, nil]
  end

  # RF-21: exact canonical key > exact config label > alias-table order >
  # lexicographic.
  def self.precedence(key, canonical, label)
    spellings = SPELLINGS.fetch(canonical, [])
    rank = if key == canonical
             0
           elsif key == label
             1
           else
             2 + (spellings.index(normalize(key)) || spellings.size)
           end
    [rank, key]
  end
  private_class_method :precedence

  def initialize(opportunity:, config:)
    @contact = opportunity.contact
    @lead_state = opportunity.lead_state
    @state_fields = lead_state.fields
    @labels = Array(config&.required_qualification_fields)
  end

  def fields
    @fields ||= labels.map do |label|
      canonical = self.class.canonical_key(label)
      value, origin = resolve(canonical, label)
      status = status_for(canonical)
      Field.new(label: label, canonical_key: canonical, value: value, origin: origin, status: status, classification: 'obrigatorio',
                satisfied: status == 'confirmado')
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

  # RF-08 proposal gate: a `concluida` qualification blocks only on required
  # fields still `faltante` (labels outside the catalog included); while
  # `em_andamento` every required field not `confirmado` blocks.
  def proposal_gate_missing_labels
    return missing_labels unless lead_state.concluida?

    fields.select { |field| field.status == 'faltante' }.map(&:label)
  end

  # RF-15: all 10 canonical keys are evaluated whether or not the config
  # requires them; only present values are sent. CT-05: `projeto` carries the
  # resolved `cliente_final` (`{{PROJETO_CLIENTE_FINAL}}`), only when present.
  def make_qualification
    qualification = MAKE_KEYS.index_with { |canonical| resolved_value(canonical) }
    qualification['projeto'] = resolved_value('cliente_final')
    qualification.compact_blank
  end

  private

  attr_reader :contact, :lead_state, :state_fields, :labels

  def status_for(canonical)
    return 'faltante' unless CATALOG_KEYS.include?(canonical)

    state_fields.dig(canonical, 'status') || 'faltante'
  end

  def resolved_value(canonical)
    label = fields.find { |field| field.canonical_key == canonical }&.label
    resolve(canonical, label).first
  end

  def resolve(canonical, label)
    entry = state_fields[canonical]
    return [entry['value'], 'lead_state'] if entry && entry['status'] != 'faltante'

    self.class.contact_resolution(contact, canonical, label)
  end
end
