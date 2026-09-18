# RF-48 "emit a cadence/workflow signal" -- records that a cadence-relevant
# event happened for an opportunity (stage change, full/partial reply, won,
# lost, opt-out, manual pause). The cadence engine itself (a later phase,
# RF-57-RF-69) is the eventual consumer of these signals; this action's
# scope here is limited to what T38's executor already guarantees: schema
# validation, idempotency, and an audit trail entry any future cadence
# listener can read.
class ScanSolo::Actions::CadenceSignalAction
  CLASSIFICATION = :automatic

  SIGNALS = %w[full_reply partial_reply stage_changed won lost opt_out manual_pause].freeze

  SCHEMA = {
    'type' => 'object',
    'properties' => {
      'opportunity_id' => { 'type' => 'integer' },
      'signal' => { 'type' => 'string', 'enum' => SIGNALS }
    },
    'required' => %w[opportunity_id signal],
    'additionalProperties' => false
  }.freeze

  def self.call(params:, **)
    new(params: params).call
  end

  def initialize(params:)
    @params = params
  end

  def call
    opportunity = ScanSolo::PipelineOpportunity.find(params[:opportunity_id])

    { status: 'signal_emitted', signal: params[:signal], opportunity_id: opportunity.id }
  end

  private

  attr_reader :params
end
