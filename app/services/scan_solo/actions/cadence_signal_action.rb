# RF-48 "emit a cadence/workflow signal" -- records that a cadence-relevant
# event happened for an opportunity (stage change, full/partial reply, won,
# lost, opt-out, manual pause). RF-56/RF-66's stop/recalculate triggers
# (opt_out, manual_pause, and cadence replacement/cancellation) route
# through ScanSolo::Cadence::StopRecalculatePolicy (T53) here -- a fixed,
# explicit enum value chosen by the caller, never free-text/NLP-derived
# timing (RF-69). `full_reply`/`partial_reply`/`stage_changed`/`won`/`lost`
# are deliberately NOT wired to the policy from here: full/partial reply
# detection is ScanSolo::Cadence::ReplyCompletenessDetector's deterministic
# field-completeness rule alone (RF-65), and stage_changed/won/lost are
# already driven by ScanSolo::Pipeline::StageTransitionService itself, so
# wiring them here too would double-apply the same stop/recalculate.
class ScanSolo::Actions::CadenceSignalAction
  CLASSIFICATION = :automatic

  SIGNALS = %w[full_reply partial_reply stage_changed won lost opt_out manual_pause].freeze
  POLICY_TRIGGERS = %w[opt_out manual_pause].freeze

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
    signal = params[:signal].to_s

    ScanSolo::Cadence::StopRecalculatePolicy.call(opportunity: opportunity, trigger: signal) if POLICY_TRIGGERS.include?(signal)

    { status: 'signal_emitted', signal: signal, opportunity_id: opportunity.id }
  end

  private

  attr_reader :params
end
