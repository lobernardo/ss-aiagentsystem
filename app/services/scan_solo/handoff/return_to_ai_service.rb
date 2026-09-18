# CT-05 / RF-52 / RF-53: the sole code path allowed to clear a
# human-controlled/paused state back to `ai_active` (RF-52's "no other code
# path" guarantee). Idempotent: a repeat call while already `ai_active` is
# a no-op, producing no duplicate audit entry beyond the first (RF-53).
class ScanSolo::Handoff::ReturnToAiService
  def self.call(conversation:, actor:)
    new(conversation: conversation, actor: actor).call
  end

  def initialize(conversation:, actor:)
    @conversation = conversation
    @actor = actor
  end

  def call
    extension = ScanSolo::ConversationExtension.resolve_for(conversation)
    return extension if extension.ai_active?

    extension.update!(ai_control_state: :ai_active)

    ScanSolo::AuditLogger.record!(
      subject: extension,
      event_type: 'handoff.return_to_ai',
      actor: actor,
      correlation_id: SecureRandom.uuid,
      payload: { conversation_id: conversation.id }
    )

    extension
  end

  private

  attr_reader :conversation, :actor
end
