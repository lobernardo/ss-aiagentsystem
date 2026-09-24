# RF-48 "emit a cadence/workflow signal" -- records that a cadence-relevant
# event happened for an opportunity (stage change, full/partial reply, won,
# lost, opt-out, manual pause). `opt_out` persists the contact's opt-out
# marker through ScanSolo::OptOut::MarkService (RF-16 (a)), which also
# cancels the contact's open enrollments; `manual_pause` routes through
# ScanSolo::Cadence::StopRecalculatePolicy (T53) here -- a fixed,
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

    case signal
    when 'opt_out'
      ScanSolo::OptOut::MarkService.call(contact: opportunity.contact, source: 'model_action')
    when 'manual_pause'
      ScanSolo::Cadence::StopRecalculatePolicy.call(opportunity: opportunity, trigger: signal)
    end

    { status: 'signal_emitted', signal: signal, opportunity_id: opportunity.id }
  end

  private

  attr_reader :params
end
