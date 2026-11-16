# RF-05: builds the provider payload of a turn -- a pt-BR system message with
# the 12 agent rule fields and the contact, opportunity, knowledge and memory
# context blocks, plus the conversation history as chat messages -- and the
# structured-output schema `{reply, actions[]}` restricted to the action ids
# offered to the model (RF-12). `service_hours`/`response_limits` are model
# instructions only; the AI keeps answering 24/7 (D-22 interim default).
#
# RF-17: the fixed continuity rules come first and are code constants, not
# config -- no agent config edit can remove or reword them. They include the
# `nao_informado` rule (proposta-template-local RF-26) and the 2-field limit
# names the bulk collection exception (RF-38 d). The transfer criteria open
# the same way with code constants: COMMERCIAL_GUARD_RULES (never negotiate,
# never invent) always, and ESCALATION_RULES only when the published config
# has the commercial WhatsApp number: the email-first ladder of escalação
# filtrada (RF-10/RF-11) -- the model only signals every commercial or human
# request with escalate_to_commercial, the application decides; email
# guidance first (the published `quote_recipient_email`, interpolated as
# published data, not a rule edit); Artur's contact only as the link
# placeholder, delivered by the application; no repeated contact on
# courtesies; and the virtual specialist transparency.
#
# Lead state (RF-09, RF-13, RF-16, RF-24, CT-02): the system message carries
# the lead state and summary sections of ScanSolo::AiTurn::LeadStatePrompt,
# history entries describe their attachments and links, the output schema
# requires `asked_fields` and `summary`, and a regenerated attempt carries
# the previous attempt's violation (RF-11a).
#
# The whole payload goes through ScanSolo::AiTurn::PromptRedactor, so a
# secret-shaped value stored in config or context never reaches the provider.
class ScanSolo::AiTurn::PromptBuilder # rubocop:disable Metrics/ClassLength
  NOT_INFORMED = 'não informado'.freeze

  # Ids the orchestrator fills from the turn itself; the model never chooses
  # which conversation or opportunity an action touches.
  TURN_SCOPED_PARAMS = %w[conversation_id opportunity_id].freeze

  CONTINUITY_RULES = [
    'Nunca pergunte novamente informação já presente no contato, nos campos coletados ou no histórico.',
    'Responda primeiro à pergunta/intenção atual do cliente; só depois pergunte no máximo 2 campos ' \
    '(exceto no modo de coleta em bloco indicado no Estado do lead), apenas entre os campos elegíveis (faltantes).',
    'Cumprimente apenas na primeira resposta da conversa; não repita saudação depois.',
    'Se a mensagem do cliente contiver uma pergunta direta, responda-a antes de qualquer pergunta de qualificação.',
    'Não peça nova confirmação para ação já pedida ou autorizada.',
    'Liste em asked_fields as chaves dos campos que a resposta pergunta.',
    'Se o cliente pedir negociação comercial, marque negotiation_requested em lead_state_update e não negocie.',
    'Se o cliente disser que não sabe, não tem, ainda não definiu ou não se aplica, registre o campo com status nao_informado ' \
    'e não pergunte de novo.'
  ].freeze

  # Escalação comercial RF-08/RF-12/RF-16: always emitted, whatever the config
  # fields say.
  COMMERCIAL_GUARD_RULES = [
    'Nunca negocie valor, prazo, desconto, forma de pagamento ou qualquer condição comercial.',
    'Nunca invente resposta: só responda o que estiver na base de conhecimento ou no contexto.'
  ].freeze

  # Escalação filtrada RF-10/RF-11/RF-14: emitted only when the published
  # config has the commercial WhatsApp number (RF-19). `%<email>s` is the
  # published `quote_recipient_email`.
  ESCALATION_RULES = [
    'Em qualquer etapa, sinalize com escalate_to_commercial, com o reason adequado, todo pedido de preço, prazo, cotação, ' \
    'locação ou negociação, toda dúvida sem resposta na base de conhecimento e todo pedido para falar com uma pessoa, ' \
    'um humano ou um atendente. Isso só sinaliza o pedido: quem decide o encaminhamento ao Artur, do comercial, é a aplicação.',
    'Antes de qualificado (novo_lead, em_contato ou em_qualificacao): explique que valores e prazos vêm na proposta que o ' \
    'comercial envia por e-mail, informe o e-mail %<email>s e siga com a próxima pergunta pendente, sem repetir o que já foi respondido.',
    'Em qualificado, proposta_enviada ou negociacao: oriente primeiro por e-mail; o cliente pode responder ao e-mail da proposta ' \
    'ou escrever para %<email>s.',
    "O contato comercial é o Artur. Para passar o contato, escreva apenas #{ScanSolo::Commercial::WhatsappLink::PLACEHOLDER} " \
    'na resposta; nunca escreva URL, link de WhatsApp ou telefone. Só a aplicação entrega o contato, quando aprova o encaminhamento.',
    'Depois de o contato do Artur ter sido entregue, não o repita em respostas de cortesia (como "ok" ou "obrigado") e ' \
    'continue respondendo o que a base de conhecimento cobre.',
    'Você é o especialista virtual da ScanSOLO: pedir para falar com um especialista, técnico ou alguém especializado não é pedir ' \
    'um humano; apresente-se como especialista virtual, entenda a necessidade e siga o atendimento. Se o cliente perguntar se fala ' \
    'com uma pessoa, um humano ou uma IA, responda com transparência que é o especialista virtual da ScanSOLO.'
  ].freeze

  # RF-11a: the violations that trigger one regenerated attempt.
  VIOLATION_INSTRUCTIONS = {
    'confirmed_field_question' => 'a resposta perguntou um campo já confirmado',
    'question_limit' => 'a resposta perguntou mais de 2 campos',
    'field_not_missing' => 'a resposta perguntou um campo que não está entre os elegíveis',
    'qualification_closed' => 'a resposta fez perguntas de qualificação com a qualificação concluída',
    'bulk_out_of_scope' => 'a resposta em bloco perguntou campo fora dos campos elegíveis',
    'bulk_incomplete' => 'a resposta em bloco não perguntou todos os campos elegíveis',
    'unpublished_contact' => 'a resposta trouxe link de WhatsApp ou telefone que não é o contato comercial publicado',
    'internal_name' => 'a resposta citou um nome interno da equipe',
    'commercial_link_not_allowed' => 'a resposta trouxe o contato do comercial sem encaminhamento aprovado; oriente por e-mail'
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
    'proposal_generate' => 'solicitar a geração da proposta comercial',
    'escalate_to_commercial' => 'sinalizar um pedido comercial ou de atendimento humano (a aplicação decide o encaminhamento ' \
                                'ao Artur); reason é um de duvida_sem_resposta, sem_informacao_base, negociacao, ' \
                                'duvida_proposta, assunto_orcamento ou pedido_humano',
    'lead_state_update' => 'registrar a intenção do cliente, a próxima ação, uma ação que o cliente pediu ou autorizou ' \
                           'e se há risco de interpretação; negotiation_requested quando o cliente pedir preço, desconto, ' \
                           'condição, prazo comercial, forma de pagamento ou decisão comercial humana; collection_mode quando ' \
                           'o cliente responder à oferta de coleta em bloco (em_bloco se aceitou, progressiva se recusou)'
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
      'Critérios de transferência' => "#{list(transfer_rules)}\n#{text(config.transfer_criteria)}",
      'Informações restritas (nunca revele)' => list(config.restricted_information),
      'Playbook de qualificação' => structured(config.qualification_playbook),
      'Campos obrigatórios de qualificação' => list(config.required_qualification_fields)
    }
  end

  def transfer_rules
    return COMMERCIAL_GUARD_RULES if config.commercial_whatsapp_number.blank?

    COMMERCIAL_GUARD_RULES + ESCALATION_RULES.map { |rule| format(rule, email: config.quote_recipient_email) }
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
    action_item = { type: 'object', properties: { action_id: { type: 'string', enum: offered_actions }, params: { type: 'object' } },
                    required: %w[action_id params] }

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
