# Relatórios RF-05/RF-06: the single stall-reason rule. Given a stalled
# opportunity, returns the first RF-05 reason whose condition holds (fixed
# precedence) and its suggested action (i18n key). Pure: reads only the
# preloaded `conversation_extension` and `cadence_enrollments` (with
# `cadence_definition` and `attempts`) -- no queries, no writes (RNF-03).
# `legacy_bulk` is precomputed by the caller from the
# `quote_request.handled_manually` audit with `cadence_skipped = legacy_bulk`.
class ScanSolo::Reports::StallReason
  REASONS = %w[
    em_atendimento_humano
    aguardando_artur
    cadencia_bloqueada_template_meta
    followup_vencido_nao_enviado
    proposta_manual_sem_cadencia
    sem_followup_agendado
    cadencia_concluida_sem_resposta
    aguardando_resposta_do_lead
    qualificado_sem_encaminhamento
    outro
  ].freeze

  SUGGESTED_ACTIONS = REASONS.index_with { |reason| "SCANSOLO.REPORTS.SUGGESTED_ACTIONS.#{reason.upcase}" }.freeze

  # Block reasons written by ScanSolo::Cadence::TemplateAvailabilityGuard.
  TEMPLATE_BLOCK_REASONS = %w[template_missing params_mismatch].freeze

  def self.call(opportunity:, now:, commercial_status:, legacy_bulk:)
    reason = new(opportunity: opportunity, now: now, commercial_status: commercial_status, legacy_bulk: legacy_bulk).reason
    { stall_reason: reason, suggested_action: SUGGESTED_ACTIONS.fetch(reason) }
  end

  def initialize(opportunity:, now:, commercial_status:, legacy_bulk:)
    @opportunity = opportunity
    @now = now
    @commercial_status = commercial_status
    @legacy_bulk = legacy_bulk
  end

  def reason # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return 'em_atendimento_humano' if human_attended?
    return 'aguardando_artur' if commercial_status == 'aguardando_artur'
    return 'cadencia_bloqueada_template_meta' if active_scheduled_attempts.any? { |attempt| template_blocked?(attempt) }
    return 'followup_vencido_nao_enviado' if active_scheduled_attempts.any? { |attempt| attempt.scheduled_at < now }
    return 'proposta_manual_sem_cadencia' if legacy_bulk && commercial_status == 'proposta_enviada_manual'
    return 'sem_followup_agendado' if without_follow_up?
    return 'cadencia_concluida_sem_resposta' if enrollment&.completed?
    # Every scheduled attempt left here is due at or after `now` (row 4 took the overdue ones).
    return 'aguardando_resposta_do_lead' if active_scheduled_attempts.any?
    return 'qualificado_sem_encaminhamento' if opportunity.qualificado? && commercial_status == 'nao_encaminhado'

    'outro'
  end

  private

  attr_reader :opportunity, :now, :commercial_status, :legacy_bulk

  def human_attended?
    opportunity.conversation_extension.present? && !opportunity.conversation_extension.ai_active?
  end

  def template_blocked?(attempt)
    TEMPLATE_BLOCK_REASONS.include?(attempt.last_block_reason)
  end

  def without_follow_up?
    return false unless ScanSolo::Cadence::StageEntryEnroller::STAGES.include?(opportunity.stage)
    return true if enrollment.nil? || enrollment.cancelled?

    (enrollment.active? || enrollment.paused?) && scheduled_attempts.empty?
  end

  def active_scheduled_attempts
    enrollment&.active? ? scheduled_attempts : []
  end

  def scheduled_attempts
    @scheduled_attempts ||= enrollment.attempts.select(&:scheduled?)
  end

  # "Inscrição da etapa atual": the most recent enrollment whose definition
  # belongs to the current stage, filtered in Ruby over the preloaded list.
  def enrollment
    return @enrollment if defined?(@enrollment)

    @enrollment = opportunity.cadence_enrollments
                             .select { |candidate| candidate.cadence_definition.stage == opportunity.stage }
                             .max_by { |candidate| [candidate.created_at, candidate.id] }
  end
end
