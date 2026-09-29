# Lead state RF-21, RF-23, RF-04: concludes the qualification the first time
# every required field is `confirmado`, as a deterministic consequence of
# the state after all actions of a turn attempt (not a model action). The
# ScanSolo::Qualification::FieldResolver decides satisfaction; an empty
# required list never concludes, and `inferido` never counts.
#
# On completion, in the caller's transaction:
# 1. the qualification becomes `concluida` (it never reopens, whatever the
#    intent or config does later);
# 2. the stage moves to `qualificado` only through
#    ScanSolo::Pipeline::StageTransitionService -- `novo_lead`/`em_contato`
#    pass through `em_qualificacao`, one stage event per transition; an
#    opportunity already at or past `qualificado` keeps its stage;
# 3. the next action recorded by the model in this turn stays, otherwise the
#    default of the current intent is recorded;
# 4. one `lead_state.qualification_completed` audit event carries the turn's
#    correlation id.
class ScanSolo::LeadState::CompletionService
  STAGE_PATH = {
    'novo_lead' => %w[em_qualificacao qualificado],
    'em_contato' => %w[em_qualificacao qualificado],
    'em_qualificacao' => %w[qualificado]
  }.freeze

  def self.call(opportunity:, turn:)
    new(opportunity: opportunity, turn: turn).call
  end

  def initialize(opportunity:, turn:)
    @opportunity = opportunity
    @turn = turn
  end

  def call
    # The turn's actions write through their own records.
    opportunity.reload
    return if lead_state.concluida? || !all_required_confirmed?

    writer = ScanSolo::LeadState::Writer.new(lead_state: lead_state)
    writer.complete!(at: Time.current)
    advance_stage!
    unless lead_state.next_action_source_message_id == turn.message_id
      writer.record_next_action!(value: ScanSolo::LeadState::DEFAULT_NEXT_ACTION_BY_INTENT[lead_state.intent], source_message_id: turn.message_id)
    end
    record_audit!
  end

  private

  attr_reader :opportunity, :turn

  def lead_state
    opportunity.lead_state
  end

  def all_required_confirmed?
    config = ScanSolo::AiAgentConfig.published_for(opportunity.account)
    resolver = ScanSolo::Qualification::FieldResolver.call(opportunity: opportunity, config: config)
    resolver.fields.present? && resolver.missing_labels.empty?
  end

  def advance_stage!
    STAGE_PATH.fetch(opportunity.stage, []).each do |stage|
      ScanSolo::Pipeline::StageTransitionService.new(opportunity: opportunity, target_stage: stage).call
    end
  end

  def record_audit!
    ScanSolo::AuditLogger.record!(
      subject: lead_state, event_type: 'lead_state.qualification_completed', correlation_id: turn.correlation_id,
      payload: { opportunity_id: opportunity.id, next_action: lead_state.next_action, stage: opportunity.stage }
    )
  end
end
