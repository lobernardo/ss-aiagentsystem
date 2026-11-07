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
# 3. the next action becomes `proposta`, whatever the intent or the model
#    recorded: a qualification with every required field is always sent to
#    the commercial team;
# 4. one `lead_state.qualification_completed` audit event carries the turn's
#    correlation id;
# 5. ScanSolo::QuoteRequestJob is enqueued only after every open transaction
#    commits, so a rolled-back attempt requests no quote (RF-12).
# Returns true only on the call that concludes, so the attempt answers with
# the completion reply (ScanSolo::AiTurn::AttemptRunner).
class ScanSolo::LeadState::CompletionService
  STAGE_PATH = {
    'novo_lead' => %w[em_qualificacao qualificado],
    'em_contato' => %w[em_qualificacao qualificado],
    'em_qualificacao' => %w[qualificado]
  }.freeze
  NEXT_ACTION = 'proposta'.freeze

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
    return false if lead_state.concluida? || !all_required_confirmed?

    writer = ScanSolo::LeadState::Writer.new(lead_state: lead_state)
    writer.complete!(at: Time.current)
    advance_stage!
    writer.record_next_action!(value: NEXT_ACTION, source_message_id: turn.message_id) unless lead_state.next_action == NEXT_ACTION
    record_audit!
    request_quote!
    true
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

  def request_quote!
    opportunity_id = opportunity.id
    ActiveRecord.after_all_transactions_commit { ScanSolo::QuoteRequestJob.perform_later(opportunity_id) }
  end

  def record_audit!
    ScanSolo::AuditLogger.record!(
      subject: lead_state, event_type: 'lead_state.qualification_completed', correlation_id: turn.correlation_id,
      payload: { opportunity_id: opportunity.id, next_action: lead_state.next_action, stage: opportunity.stage }
    )
  end
end
