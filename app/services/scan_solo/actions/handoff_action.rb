# RF-48 "request human handoff" -- flips the conversation's AI-control
# state to handoff_requested via ScanSolo::ConversationExtension (T07), the
# same field ScanSolo::AiTurn::EligibilityGuard reads to suppress further
# automatic AI turns (RF-37). The richer private-note-with-nine-elements
# handoff builder (RF-51) is a dedicated later-phase service (T41); this
# action only guarantees the state flip itself.
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
    extension = ScanSolo::ConversationExtension.resolve_for(conversation)
    extension.update!(ai_control_state: :handoff_requested)

    { status: 'handoff_requested', conversation_id: conversation.id, reason: params[:reason] }
  end

  private

  attr_reader :params
end
