# Sole call path for changing ScanSolo::PipelineOpportunity#stage (RF-19): a
# rejected transition raises ActiveRecord::RecordInvalid so it maps to the
# existing global 422 handler without any bespoke controller-side rescue.
#
# RF-66: every successful transition stops/recalculates pending cadence
# work through ScanSolo::Cadence::StopRecalculatePolicy (T53) -- ganho/
# perdido map to their own dedicated triggers, any other stage change maps
# to the generic `stage_changed` trigger. Once the previous cadence work is
# stopped, the new stage's cadence is enrolled through
# ScanSolo::Cadence::StageEntryEnroller (RF-24).
class ScanSolo::Pipeline::StageTransitionService
  TERMINAL_STAGES = %w[ganho perdido].freeze
  GUARDED_STAGES = %w[negociacao].freeze
  CADENCE_TRIGGERS = { 'ganho' => 'won', 'perdido' => 'lost' }.freeze

  def initialize(opportunity:, target_stage:, actor: nil, authorized: false)
    @opportunity = opportunity
    @target_stage = target_stage.to_s
    @actor = actor
    @authorized = authorized
  end

  def call
    validate_target_stage!
    validate_not_terminal!
    validate_guarded_stage!

    previous_stage = opportunity.stage

    ActiveRecord::Base.transaction do
      opportunity.update!(stage: target_stage)
      ScanSolo::PipelineStageEvent.create!(
        opportunity: opportunity,
        from_stage: previous_stage,
        to_stage: target_stage,
        actor: actor
      )
    end

    ScanSolo::Cadence::StopRecalculatePolicy.call(opportunity: opportunity, trigger: cadence_trigger)
    ScanSolo::Cadence::StageEntryEnroller.call(opportunity: opportunity)

    opportunity
  end

  private

  attr_reader :opportunity, :target_stage, :actor, :authorized

  def cadence_trigger
    CADENCE_TRIGGERS.fetch(target_stage, 'stage_changed')
  end

  def validate_target_stage!
    return if ScanSolo::PipelineOpportunity.stages.key?(target_stage)

    reject!(:stage, "must be one of #{ScanSolo::PipelineOpportunity.stages.keys.join(', ')}")
  end

  def validate_not_terminal!
    return unless TERMINAL_STAGES.include?(opportunity.stage)

    reject!(:base, 'opportunity stage is terminal and cannot transition further')
  end

  def validate_guarded_stage!
    return unless GUARDED_STAGES.include?(target_stage)
    return if authorized

    reject!(:stage, 'negociacao requires an explicit authorized action')
  end

  def reject!(attribute, message)
    opportunity.errors.add(attribute, message)
    raise ActiveRecord::RecordInvalid, opportunity
  end
end
