# Escalação comercial RF-03/RF-06/RF-10/RF-11/CT-02: the model-driven
# escalation to the public commercial contact. Only writes the mark through
# ScanSolo::Commercial::EscalationService: no handoff, no cadence trigger and
# no message (the wa.me link travels inside the turn's single reply), so the
# AI stays `ai_active`.
class ScanSolo::Actions::EscalateToCommercialAction
  CLASSIFICATION = :automatic

  SCHEMA = {
    'type' => 'object',
    'properties' => {
      'conversation_id' => { 'type' => 'integer' },
      'reason' => { 'type' => 'string', 'enum' => ScanSolo::PipelineOpportunity::ESCALATION_REASONS }
    },
    'required' => %w[conversation_id reason],
    'additionalProperties' => false
  }.freeze

  def self.call(params:, turn:, **)
    opportunity = ScanSolo::PipelineOpportunity.find_by!(conversation_id: params[:conversation_id])
    ScanSolo::Commercial::EscalationService.call(opportunity: opportunity, reason: params[:reason], turn: turn)
  end
end
