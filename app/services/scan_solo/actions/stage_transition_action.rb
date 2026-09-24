# RF-48 "request a pipeline stage transition" -- the AI's only way to move an
# opportunity, delegating to ScanSolo::Pipeline::StageTransitionService (the
# sole stage writer). RF-14: the AI may only move forward to em_qualificacao
# or qualificado; any other target (negociacao, ganho, perdido,
# proposta_enviada, or a backward move) is rejected without touching the
# stage, and the rejection is returned so it lands in the turn's
# action_evidence.
class ScanSolo::Actions::StageTransitionAction
  CLASSIFICATION = :automatic

  AI_TARGET_STAGES = %w[em_qualificacao qualificado].freeze

  SCHEMA = {
    'type' => 'object',
    'properties' => {
      'opportunity_id' => { 'type' => 'integer' },
      'target_stage' => { 'type' => 'string' }
    },
    'required' => %w[opportunity_id target_stage],
    'additionalProperties' => false
  }.freeze

  def self.call(params:, actor: nil, **)
    new(params: params, actor: actor).call
  end

  def initialize(params:, actor: nil)
    @params = params
    @actor = actor
  end

  def call
    opportunity = ScanSolo::PipelineOpportunity.find(params[:opportunity_id])
    from_stage = opportunity.stage
    target_stage = params[:target_stage].to_s

    unless allowed?(from_stage, target_stage)
      return { status: 'rejected', reason: 'stage_not_allowed_for_ai', from_stage: from_stage, target_stage: target_stage }
    end

    ScanSolo::Pipeline::StageTransitionService.new(opportunity: opportunity, target_stage: target_stage, actor: actor).call
    { status: 'transitioned', from_stage: from_stage, to_stage: target_stage }
  end

  private

  attr_reader :params, :actor

  def allowed?(from_stage, target_stage)
    stages = ScanSolo::PipelineOpportunity.stages
    AI_TARGET_STAGES.include?(target_stage) && stages.fetch(target_stage) > stages.fetch(from_stage)
  end
end
