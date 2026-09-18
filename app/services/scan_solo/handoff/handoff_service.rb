# RF-50/RF-51/RF-52: the sole builder of the nine-element handoff private
# note. Invoked both by a human-initiated takeover (T42's TakeoverService)
# and, in principle, by any other handoff entry point -- it is idempotent
# per "handoff episode": it only builds the note and suppresses automatic
# AI replies while the conversation is still in a pre-note state
# (`ai_active` or the bare `handoff_requested` flag set by the simpler
# `human_handoff` registered action, T39, which does not itself build a
# note). Once the conversation is `awaiting_human` or further along
# (`human_active`/`paused`/`closed`), a repeat call is a no-op, guaranteeing
# "exactly one private note" per RF-51's acceptance criterion even when the
# model-initiated action and a human's explicit takeover both fire for the
# same handoff.
class ScanSolo::Handoff::HandoffService
  NEEDS_NOTE_STATES = %w[ai_active handoff_requested].freeze

  STAGE_LABELS = {
    'novo_lead' => 'Novo Lead',
    'em_contato' => 'Em Contato',
    'em_qualificacao' => 'Em Qualificação',
    'qualificado' => 'Qualificado',
    'proposta_enviada' => 'Proposta Enviada',
    'negociacao' => 'Negociação',
    'ganho' => 'Ganho',
    'perdido' => 'Perdido'
  }.freeze

  RECENT_MESSAGE_LIMIT = 3

  def self.call(conversation:, reason:, actor: nil)
    new(conversation: conversation, reason: reason, actor: actor).call
  end

  def initialize(conversation:, reason:, actor: nil)
    @conversation = conversation
    @reason = reason
    @actor = actor
  end

  def call
    return extension unless NEEDS_NOTE_STATES.include?(extension.ai_control_state)

    ActiveRecord::Base.transaction do
      create_private_note!
      extension.update!(ai_control_state: :awaiting_human)
    end

    extension
  end

  private

  attr_reader :conversation, :reason, :actor

  def extension
    @extension ||= ScanSolo::ConversationExtension.resolve_for(conversation)
  end

  def opportunity
    @opportunity ||= ScanSolo::PipelineOpportunity.find_by(conversation_id: conversation.id)
  end

  def contact
    @contact ||= conversation.contact
  end

  def create_private_note!
    Messages::MessageBuilder.new(actor, conversation, { content: note_content, private: true }).perform
  end

  def note_content
    <<~NOTE.strip
      Motivo da transferência: #{reason}
      Resumo: #{summary}
      Objetivo do cliente: #{customer_objective}
      Campos de qualificação coletados: #{qualification_fields}
      Objeções: #{objections}
      Etapa do pipeline: #{pipeline_stage}
      Status da proposta: #{proposal_status}
      Ações pendentes: #{pending_actions}
      Próximo passo recomendado: #{recommended_next_step}
    NOTE
  end

  def summary
    recent_messages = conversation.messages.chat.order(created_at: :desc).limit(RECENT_MESSAGE_LIMIT).reload.reverse
    return 'sem histórico de mensagens' if recent_messages.blank?

    recent_messages.map { |m| "#{m.incoming? ? 'Cliente' : 'Agente'}: #{m.content}" }.join(' | ')
  end

  def customer_objective
    return 'não informado' if contact.blank?

    contact.custom_attributes['objective'].presence || 'não informado'
  end

  def qualification_fields
    return 'nenhum' if contact.blank?

    allowed = Array(ScanSolo::AiAgentConfig.published_for(conversation.account)&.required_qualification_fields)
    collected = contact.custom_attributes.slice(*allowed).compact
    return 'nenhum' if collected.blank?

    collected.map { |field, value| "#{field}: #{value}" }.join(', ')
  end

  def objections
    return 'nenhuma registrada' if contact.blank?

    contact.custom_attributes['objections'].presence || 'nenhuma registrada'
  end

  def pipeline_stage
    return 'sem oportunidade associada' if opportunity.blank?

    STAGE_LABELS.fetch(opportunity.stage, opportunity.stage)
  end

  # No ScanSolo proposal module exists yet -- mirrors
  # ScanSolo::AiTurn::ContextAssembler's explicit not-applicable marker for
  # proposal_context rather than a silently absent element.
  def proposal_status
    'não aplicável'
  end

  def pending_actions
    return 'nenhuma' if opportunity.blank?

    turn_ids = ScanSolo::AiTurn.where(conversation_id: conversation.id).select(:id)
    action_ids = ScanSolo::AgentActionExecution.where(turn_id: turn_ids, status: :pending).distinct.pluck(:action_id)
    return 'nenhuma' if action_ids.blank?

    action_ids.join(', ')
  end

  def recommended_next_step
    'Revisar o histórico da conversa e responder diretamente ao cliente.'
  end
end
