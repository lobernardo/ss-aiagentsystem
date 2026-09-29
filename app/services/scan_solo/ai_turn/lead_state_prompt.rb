# RF-09, RF-15, RF-22, RF-24, RF-25: the `## Estado do lead` and
# `## Resumo dos dados` sections of the ScanSolo::AiTurn::PromptBuilder
# system message, rendered from the ContextAssembler's `lead_state_context`
# (the ScanSolo::LeadState::Projection plus `summary_allowed`): confirmed and
# inferred values, required fields not yet confirmed, the ordered eligible
# keys (none once the qualification is `concluida`), the intent with exactly
# one script line, the authorized actions and whether a full data summary is
# allowed this turn.
class ScanSolo::AiTurn::LeadStatePrompt
  # RF-15: one script line per intent (and for the not yet classified one);
  # the intent never changes which fields are required.
  INTENT_SCRIPTS = {
    'orcamento' => 'o cliente quer um orçamento: colete os dados do serviço e do local para encaminhar a proposta.',
    'avaliacao_tecnica' => 'o cliente quer uma avaliação técnica: entenda o problema e o local para encaminhar a avaliação.',
    'convite_cotacao' => 'o cliente enviou um convite para cotação: identifique o escopo, os documentos e o prazo para proposta.',
    'envio_documentos' => 'o cliente está enviando documentos: confirme o recebimento e registre os dados que eles trazem.',
    'duvida' => 'o cliente tem uma dúvida: responda com base no conhecimento disponível antes de qualificar.',
    'verificar_capacidade' => 'o cliente quer saber se atendemos o caso: explique a capacidade técnica e colete o essencial.',
    'localizar_rede' => 'o cliente quer localizar redes ou interferências: entenda o que busca e onde fica o local.',
    'visita' => 'o cliente quer uma visita: colete o local e a data desejada para encaminhar a avaliação técnica.',
    'acompanhar_proposta' => 'o cliente acompanha uma proposta já pedida: informe que a equipe dá retorno, sem requalificar.',
    'outro' => 'o pedido não se encaixa nas demais intenções: entenda a necessidade antes de qualificar.',
    nil => 'intenção ainda não classificada: entenda o que o cliente precisa e registre a intenção em lead_state_update.'
  }.freeze

  SUMMARY_EXCEPTION = 'exceto se esta resposta concluir a qualificação, registrar next_action, pedir human_handoff, ' \
                      'mudar a etapa ou declarar interpretation_risk'.freeze

  CATALOG_LABELS = ScanSolo::Qualification::FieldResolver::CATALOG.to_h { |entry| [entry[:key], entry[:label]] }.freeze

  def self.call(lead_state_context:)
    new(lead_state_context).call
  end

  def initialize(lead_state_context)
    @state = lead_state_context
  end

  def call
    { 'Estado do lead' => lead_state_block, 'Resumo dos dados' => summary_block }
  end

  private

  attr_reader :state

  def lead_state_block
    return 'sem oportunidade associada' if state[:available] == false

    [*status_lines, *field_lines, *eligible_lines].join("\n")
  end

  def status_lines
    [
      "Etapa: #{ScanSolo::Handoff::HandoffService::STAGE_LABELS.fetch(state[:status][:stage].to_s)}",
      "Status da qualificação: #{state[:qualification][:status]}",
      "Intenção: #{state[:intent] || 'não classificada'}",
      "Roteiro da intenção: #{INTENT_SCRIPTS.fetch(state[:intent])}",
      "Próxima ação: #{state.dig(:next_action, :value) || 'nenhuma'}",
      "Ações autorizadas (já pedidas ou autorizadas pelo cliente, não peça confirmação):\n#{authorized_actions}"
    ]
  end

  def field_lines
    [
      "Campos confirmados:\n#{list(fields_with('confirmado').map { |field| "#{field[:label]}: #{field[:value]}" })}",
      "Campos inferidos (não confirmados pelo cliente):\n" \
      "#{list(fields_with('inferido').map { |field| "#{field[:label]}: #{field[:value]} (inferido)" })}",
      "Campos obrigatórios não confirmados:\n#{list(state[:status][:missing_fields].map { |key| field_reference(key) })}"
    ]
  end

  def fields_with(status)
    state[:blocks].values.flatten.select { |field| field[:status] == status }
  end

  def authorized_actions
    actions = state[:authorized_actions].pluck(:action)
    actions.empty? ? 'nenhuma' : list(actions)
  end

  # RF-09, RF-22: the only keys the reply may ask about, in order.
  def eligible_lines
    if state[:qualification][:status] == 'concluida'
      return ['Próximos campos elegíveis: nenhum', 'Qualificação concluída: não faça perguntas de qualificação.']
    end

    ["Próximos campos elegíveis:\n#{list(state[:eligible_keys].map { |key| field_reference(key) })}"]
  end

  def field_reference(key)
    "#{key} (#{CATALOG_LABELS.fetch(key, key)})"
  end

  # RF-25: deterministic indicator; the fixed exception lets the reply that
  # produces one of the events carry the summary.
  def summary_block
    return 'resumo permitido: pode enviar o resumo completo dos dados.' if state[:summary_allowed]

    "resumo não permitido: não envie o resumo completo dos dados, #{SUMMARY_EXCEPTION}."
  end

  def list(values)
    values.empty? ? 'nenhum' : values.map { |value| "- #{value}" }.join("\n")
  end
end
