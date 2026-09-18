# RF-48 "request a pipeline stage transition" -- delegates entirely to
# ScanSolo::Pipeline::StageTransitionService (T12), the sole call path for
# changing a PipelineOpportunity's stage, so RF-09/RF-18/RF-19's guards
# apply here exactly as they do to every other caller.
class ScanSolo::Actions::StageTransitionAction
  CLASSIFICATION = :automatic

  SCHEMA = {
    'type' => 'object',
    'properties' => {
      'opportunity_id' => { 'type' => 'integer' },
      'target_stage' => { 'type' => 'string' },
      'authorized' => { 'type' => 'boolean' }
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

    ScanSolo::Pipeline::StageTransitionService.new(
      opportunity: opportunity,
      target_stage: params[:target_stage],
      actor: actor,
      authorized: params[:authorized] || false
    ).call
  end

  private

  attr_reader :params, :actor
end
