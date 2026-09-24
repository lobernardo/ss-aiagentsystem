# RF-48/RF-15 "request human handoff": the AI's handoff goes through
# ScanSolo::Handoff::HandoffService (nine-line private note + awaiting_human,
# which stops further AI replies until return-to-AI) and pauses the
# opportunity's active cadence enrollments with the `handoff` trigger. The
# turn's own reply is still sent: the orchestrator runs actions after its
# pre-send recheck.
class ScanSolo::Actions::HandoffAction
  CLASSIFICATION = :automatic

  SCHEMA = {
    'type' => 'object',
    'properties' => {
      'conversation_id' => { 'type' => 'integer' },
      'reason' => { 'type' => 'string', 'minLength' => 1 }
    },
    'required' => %w[conversation_id reason],
    'additionalProperties' => false
  }.freeze

  def self.call(params:, **)
    new(params: params).call
  end

  def initialize(params:)
    @params = params
  end

  def call
    conversation = Conversation.find(params[:conversation_id])
    extension = ScanSolo::Handoff::HandoffService.call(conversation: conversation, reason: params[:reason])

    opportunity = ScanSolo::PipelineOpportunity.find_by(conversation_id: conversation.id)
    ScanSolo::Cadence::StopRecalculatePolicy.call(opportunity: opportunity, trigger: 'handoff')

    { status: extension.ai_control_state, conversation_id: conversation.id, reason: params[:reason] }
  end

  private

  attr_reader :params
end
