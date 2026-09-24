# CT-05 / RF-53: a human agent (or admin) explicitly taking over a
# conversation. Always routes through ScanSolo::Handoff::HandoffService
# first so the RF-51 nine-element private note exists regardless of
# whether this is the first handoff signal for the conversation or a human
# formally accepting a handoff the model already flagged (T39's simpler
# `human_handoff` registered action only sets `handoff_requested`, with no
# note) -- then promotes control to `human_active`. Idempotent: a repeat
# call while already `human_active` is a no-op, producing no duplicate
# audit entry.
#
# RF-19: also pauses (never cancels) the active cadence enrollments of this
# conversation's opportunity through
# ScanSolo::Cadence::StopRecalculatePolicy.handle_takeover -- scheduled
# attempts stay `scheduled` and are shifted on return to AI (RF-29).
#
# `trigger` records how the takeover happened in the audit payload:
# `explicit` (POST .../handoff) or `human_reply` (implicit, RF-18, from
# ScanSolo::ConversationListener).
class ScanSolo::Handoff::TakeoverService
  def self.call(conversation:, reason:, actor:, trigger: 'explicit')
    new(conversation: conversation, reason: reason, actor: actor, trigger: trigger).call
  end

  def initialize(conversation:, reason:, actor:, trigger:)
    @conversation = conversation
    @reason = reason
    @actor = actor
    @trigger = trigger
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
      payload: { conversation_id: conversation.id, reason: reason, trigger: trigger }
    )

    ScanSolo::Cadence::StopRecalculatePolicy.handle_takeover(opportunity: opportunity)

    extension
  end

  private

  attr_reader :conversation, :reason, :actor, :trigger

  def opportunity
    ScanSolo::PipelineOpportunity.find_by(conversation_id: conversation.id)
  end
end
