# CT-05 / RF-53: a human agent (or admin) explicitly taking over a
# conversation. Always routes through ScanSolo::Handoff::HandoffService
# first so the RF-51 nine-element private note exists regardless of
# whether this is the first handoff signal for the conversation or a human
# formally accepting a handoff the model already flagged (T39's simpler
# `human_handoff` registered action only sets `handoff_requested`, with no
# note) -- then promotes control to `human_active`. Idempotent: a repeat
# call while already `human_active` is a no-op, producing no duplicate
# audit entry.
class ScanSolo::Handoff::TakeoverService
  def self.call(conversation:, reason:, actor:)
    new(conversation: conversation, reason: reason, actor: actor).call
  end

  def initialize(conversation:, reason:, actor:)
    @conversation = conversation
    @reason = reason
    @actor = actor
  end

  def call
    extension = ScanSolo::ConversationExtension.resolve_for(conversation)
    return extension if extension.human_active?

    ScanSolo::Handoff::HandoffService.call(conversation: conversation, reason: reason, actor: actor)
    extension.update!(ai_control_state: :human_active)

    ScanSolo::AuditLogger.record!(
      subject: extension,
      event_type: 'handoff.takeover',
      actor: actor,
      correlation_id: SecureRandom.uuid,
      payload: { conversation_id: conversation.id, reason: reason }
    )

    extension
  end

  private

  attr_reader :conversation, :reason, :actor
end
