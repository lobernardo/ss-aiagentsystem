# Escalação comercial RF-03/RF-06/RF-10/RF-11/CT-02 + escalação filtrada
# RF-11/CT-01: the model only signals the commercial request of the turn; the
# decision belongs to ScanSolo::Commercial::EscalationService (eligibility
# gate), which returns either the escalated result or the refusal hash
# `{ escalated: false, refusal:, email_redirect_count: }` without raising. No
# handoff, no cadence trigger and no message (the wa.me link, when approved,
# travels inside the turn's single reply), so the AI stays `ai_active`.
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
