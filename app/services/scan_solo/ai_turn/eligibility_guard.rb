# Suppresses the automatic AI turn while a conversation is human-controlled
# or opted out (RF-37). Reads ScanSolo::ConversationExtension#ai_control_state
# fresh on every call rather than caching it, so a takeover recorded between
# two turns is always honored. Only `ai_active` is eligible: every other
# state (handoff_requested, awaiting_human, human_active, paused, closed) is
# a human-controlled/terminal state that must suppress the turn (RF-52's "no
# other code path" guarantee lives in the handoff module itself; this guard
# only ever reads the state, never clears it).
class ScanSolo::AiTurn::EligibilityGuard
  def self.eligible?(conversation:)
    new(conversation: conversation).eligible?
  end

  def initialize(conversation:)
    @conversation = conversation
  end

  def eligible?
    ScanSolo::ConversationExtension.resolve_for(conversation).ai_active?
  end

  private

  attr_reader :conversation
end
