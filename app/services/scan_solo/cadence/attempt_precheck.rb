# RF-04/RF-26/RF-31/RF-33: decides, under the due-attempt row lock and
# before any send, what happens to a due cadence attempt. The job owns no
# eligibility logic -- it only applies this decision.
#
# Order:
# - the account kill switch first (RF-04): with `scansolo_enabled` off
#   nothing may be consumed, not even by the cancelling checks below;
# - (1) contact opted out -> cancel (`opt_out`);
# - (2) conversation resolved -> cancel (`conversation_resolved`);
# - (3) published config / inbox eligibility (ScanSolo::Eligibility, the
#   single definition shared with the listener) or AI not in control ->
#   defer without consuming the attempt;
# - (4) template unavailable (ScanSolo::Cadence::TemplateAvailabilityGuard)
#   -> defer.
class ScanSolo::Cadence::AttemptPrecheck
  Result = Struct.new(:decision, :reason, :template, keyword_init: true) do
    def send?
      decision == :send
    end

    def cancel?
      decision == :cancel
    end
  end

  def self.call(attempt:)
    new(attempt: attempt).call
  end

  def initialize(attempt:)
    @attempt = attempt
    @opportunity = attempt.enrollment.opportunity
    @conversation = opportunity.conversation
  end

  def call
    return defer('scansolo_disabled') unless opportunity.account.scansolo_enabled?
    return cancel('opt_out') if ScanSolo::ContactExtension.opted_out?(opportunity.contact)
    return cancel('conversation_resolved') if conversation.resolved?

    eligibility = ScanSolo::Eligibility.for_inbox(account: opportunity.account, inbox: conversation.inbox)
    return defer(eligibility.reason) unless eligibility.eligible?
    return defer('human_controlled') unless ai_active?

    template_check
  end

  private

  attr_reader :attempt, :opportunity, :conversation

  def ai_active?
    extension = ScanSolo::ConversationExtension.find_by(conversation: conversation)
    extension.nil? || extension.ai_active?
  end

  def template_check
    template = ScanSolo::Messaging::TemplateResolver.call(
      account: opportunity.account, stage: attempt.enrollment.cadence_definition.stage, step: attempt.step, opportunity: opportunity
    )
    guard = ScanSolo::Cadence::TemplateAvailabilityGuard.check(inbox: conversation.inbox, template: template)
    return defer(guard.reason) if guard.blocked?

    Result.new(decision: :send, template: template)
  end

  def cancel(reason)
    Result.new(decision: :cancel, reason: reason)
  end

  def defer(reason)
    Result.new(decision: :defer, reason: reason)
  end
end
