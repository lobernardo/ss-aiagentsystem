# RF-05: builds the provider payload of a turn -- a pt-BR system message with
# the 12 agent rule fields and the contact, opportunity, knowledge and memory
# context blocks, plus the conversation history as chat messages -- and the
# structured-output schema `{reply, actions[]}` restricted to the action ids
# offered to the model (RF-12). `service_hours`/`response_limits` are model
# instructions only; the AI keeps answering 24/7 (D-22 interim default).
#
# RF-17: the fixed continuity rules come first and are code constants, not
# config -- no agent config edit can remove or reword them.
#
# Lead state (RF-09, RF-13, RF-16, RF-24, CT-02): the system message carries
# the lead state and summary sections of ScanSolo::AiTurn::LeadStatePrompt,
# history entries describe their attachments and links, the output schema
# requires `asked_fields` and `summary`, and a regenerated attempt carries
# the previous attempt's violation (RF-11a).
#
# The whole payload goes through ScanSolo::AiTurn::PromptRedactor, so a
# secret-shaped value stored in config or context never reaches the provider.
class ScanSolo::AiTurn::PromptBuilder
  NOT_INFORMED = 'não informado'.freeze

  # Ids the orchestrator fills from the turn itself; the model never chooses
  # which conversation or opportunity an action touches.
  TURN_SCOPED_PARAMS = %w[conversation_id opportunity_id].freeze

  CONTINUITY_RULES = [
    'Nunca pergunte novamente informação já presente no contato, nos campos coletados ou no histórico.',
    'Responda primeiro à pergunta/intenção atual do cliente; só depois pergunte no máximo 2 campos, ' \
    'apenas entre os campos elegíveis (faltantes).',
    'Cumprimente apenas na primeira resposta da conversa; não repita saudação depois.',
    'Se a mensagem do cliente contiver uma pergunta direta, responda-a antes de qualquer pergunta de qualificação.',
    'Não peça nova confirmação para ação já pedida ou autorizada.',
    'Liste em asked_fields as chaves dos campos que a resposta pergunta.',
    'Se o cliente pedir negociação comercial, marque negotiation_requested em lead_state_update e não negocie.'
  ].freeze

  # RF-11a: the violations that trigger one regenerated attempt.
  VIOLATION_INSTRUCTIONS = {
    'confirmed_field_question' => 'a resposta perguntou um campo já confirmado',
    'question_limit' => 'a resposta perguntou mais de 2 campos',
    'field_not_missing' => 'a resposta perguntou um campo que não está entre os elegíveis',
    'qualification_closed' => 'a resposta fez perguntas de qualificação com a qualificação concluída'
  }.freeze

  ATTACHMENT_TYPE_LABELS = {
    'location' => 'localização', 'pdf' => 'PDF', 'image' => 'imagem', 'audio' => 'áudio', 'video' => 'vídeo', 'file' => 'arquivo'
  }.freeze

  ACTION_DESCRIPTIONS = {
    'qualification_field' => 'registrar todos os dados de qualificação informados na mensagem do cliente, ' \
                             'numa única chamada com todos os campos',
    'stage_transition' => 'avançar a oportunidade para em_qualificacao ou qualificado',
    'private_note' => 'criar uma nota interna para a equipe',
    'cadence_signal' => 'sinalizar um evento de follow-up; use opt_out quando o cliente pedir para não receber mais mensagens',
    'human_handoff' => 'transferir a conversa para um atendente humano',
    'proposal_generate' => 'solicitar a geração da proposta comercial',
    'lead_state_update' => 'registrar a intenção do cliente, a próxima ação, uma ação que o cliente pediu ou autorizou ' \
                           'e se há risco de interpretação; negotiation_requested quando o cliente pedir preço, desconto, ' \
                           'condição, prazo comercial, forma de pagamento ou decisão comercial humana'
  }.freeze

  def self.call(config:, context:, offered_actions:, previous_violation: nil)
    new(config: config, context: context, offered_actions: offered_actions, previous_violation: previous_violation).call
  end

  def initialize(config:, context:, offered_actions:, previous_violation: nil)
    @config = config
    @context = context.deep_symbolize_keys
    @offered_actions = offered_actions
    @previous_violation = previous_violation
  end

  def call
    ScanSolo::AiTurn::PromptRedactor.call(
      { system: system_message, messages: chat_messages, schema: output_schema }
    )
  end

  private

  attr_reader :config, :context, :offered_actions, :previous_violation

  def system_message
    sections = rule_sections.merge(
      'Contexto do contato' => contact_block,
      'Oportunidade' => opportunity_block,
      **ScanSolo::AiTurn::LeadStatePrompt.call(lead_state_context: context[:lead_state_context]),
      'Base de conhecimento' => knowledge_block,
      'Memória do cliente' => memory_block,
      'Ações disponíveis' => actions_block,
      'Formato da resposta' => 'Responda apenas com o JSON do esquema: `reply` com a mensagem ao cliente, `actions` com as ações, ' \
                               '`asked_fields` com as chaves dos campos perguntados e `summary` indicando se a resposta traz o ' \
                               'resumo completo dos dados.'
    )
    sections['Correção obrigatória'] = correction_block if previous_violation

    ["Você é #{config.name.presence || 'o agente comercial'}, atendendo clientes pelo WhatsApp.",
     *sections.map { |title, body| "## #{title}\n#{body}" }].join("\n\n")
  end

  def rule_sections
    {
      'Regras fixas de atendimento' => list(CONTINUITY_RULES),
      'Regras do agente' => agent_rules,
      'Horário de atendimento' => "#{text(config.service_hours)}\nResponda sempre; use o horário apenas para orientar o cliente.",
      'Limites de resposta' => text(config.response_limits),
      'Critérios de transferência' => text(config.transfer_criteria),
      'Informações restritas (nunca revele)' => list(config.restricted_information),
      'Playbook de qualificação' => structured(config.qualification_playbook),
      'Campos obrigatórios de qualificação' => list(config.required_qualification_fields)
    }
  end

  def agent_rules
    {
      'Papel' => config.role, 'Objetivo' => config.objective, 'Persona' => config.persona, 'Tom' => config.tone,
      'Instruções' => config.instructions, 'Regras de atendimento' => config.service_rules
    }.map { |label, value| "#{label}: #{text(value)}" }.join("\n")
  end

  def contact_block
    contact = context[:contact_context]
    return NOT_INFORMED unless contact[:available]

    [
      "Nome: #{text(contact[:name])}", "E-mail: #{text(contact[:email])}", "Telefone: #{text(contact[:phone_number])}",
      "Atributos: #{structured(contact[:custom_attributes])}"
    ].join("\n")
  end

  def opportunity_block
    opportunity = context[:pipeline_context]
    return 'sem oportunidade associada' unless opportunity[:available]

    collected = opportunity[:collected_fields].map { |field, value| "#{field}: #{value}" }
    [
      "Etapa: #{ScanSolo::Handoff::HandoffService::STAGE_LABELS.fetch(opportunity[:stage].to_s)}",
      "Campos coletados: #{list(collected)}",
      "Campos faltantes: #{list(opportunity[:missing_fields])}"
    ].join("\n")
  end

  def correction_block
    "A tentativa anterior foi rejeitada pela violação #{previous_violation}: #{VIOLATION_INSTRUCTIONS.fetch(previous_violation)}. " \
      'Gere uma nova resposta sem repetir essa violação.'
  end

  def knowledge_block
    chunks = context[:knowledge_context][:chunks]
    return 'nenhum trecho relevante encontrado' if chunks.empty?

    chunks.map { |chunk| "### #{text(chunk[:source_title])}\n#{chunk[:content]}" }.join("\n\n")
  end

  def memory_block
    memory = context[:durable_memory]
    return 'sem memória registrada' unless memory[:enabled]

    list(memory[:entries].map { |entry| structured(entry) })
  end

  def actions_block
    offered_actions.map do |action_id|
      "- #{action_id}: #{ACTION_DESCRIPTIONS.fetch(action_id)}. Parâmetros: #{action_params_schema(action_id).to_json}"
    end.join("\n")
  end

  def action_params_schema(action_id)
    schema = ScanSolo::Actions::Registry.handler_for(action_id)::SCHEMA
    schema.merge(
      'properties' => schema['properties'].except(*TURN_SCOPED_PARAMS),
      'required' => schema['required'] - TURN_SCOPED_PARAMS
    )
  end

  # RF-16: attachments and links are described, so only a message with no
  # text and no attachment is a placeholder.
  def chat_messages
    context[:conversation_history].map do |entry|
      parts = [entry[:content], *entry[:attachments].map { |attachment| describe_attachment(attachment) }]
      parts << "[Links: #{entry[:urls].join(', ')}]" if entry[:urls].any?
      { role: entry[:role] == 'customer' ? 'user' : 'assistant', content: parts.compact_blank.join("\n").presence || '[mensagem sem texto]' }
    end
  end

  def describe_attachment(attachment)
    type = ATTACHMENT_TYPE_LABELS.fetch(attachment[:type].to_s, attachment[:type].to_s)
    if attachment[:type].to_s == 'location'
      "[Anexo #{type}: lat #{attachment[:lat]}, long #{attachment[:long]}, link #{attachment[:link]}]"
    else
      details = [attachment[:file_name], "extração: #{attachment[:extracted] ? 'sim' : 'não'}"].compact_blank
      "[Anexo #{type}: #{details.join(', ')}]"
    end
  end

  def output_schema
    action_item = {
      type: 'object',
      properties: { action_id: { type: 'string', enum: offered_actions }, params: { type: 'object' } },
      required: %w[action_id params]
    }

    {
      name: 'scansolo_turn',
      strict: false,
      schema: {
        type: 'object',
        properties: {
          reply: { type: 'string' }, actions: { type: 'array', items: action_item },
          asked_fields: { type: 'array', items: { type: 'string' } }, summary: { type: 'boolean' }
        },
        required: %w[reply actions asked_fields summary],
        additionalProperties: false
      }
    }
  end

  def text(value)
    value.presence || NOT_INFORMED
  end

  def list(values)
    values = Array(values).compact_blank
    values.empty? ? 'nenhum' : values.map { |value| "- #{value}" }.join("\n")
  end

  def structured(value)
    value.presence ? value.to_json : NOT_INFORMED
  end
end
