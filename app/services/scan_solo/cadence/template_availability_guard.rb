# RF-67: if the mapped WhatsApp template for a due attempt is unavailable/
# not approved, or automation is disabled for the account, a due attempt
# must not be sent -- a safe skip, never an unhandled error. A non-WhatsApp
# channel (a fake/test inbox, RF-71) is treated as template-available so
# cadence flows stay fully testable before a real WhatsApp number exists;
# only a real Channel::Whatsapp inbox is checked against its approved
# message_templates.
class ScanSolo::Cadence::TemplateAvailabilityGuard
  Result = Struct.new(:blocked, :reason, keyword_init: true) do
    def blocked?
      blocked
    end
  end

  def self.check(enrollment:, attempt:)
    new(enrollment: enrollment, attempt: attempt).check
  end

  def initialize(enrollment:, attempt:)
    @enrollment = enrollment
    @attempt = attempt
  end

  def check
    return Result.new(blocked: true, reason: 'automation_disabled') unless automation_enabled?
    return Result.new(blocked: true, reason: 'template_unavailable') unless template_available?

    Result.new(blocked: false, reason: nil)
  end

  private

  attr_reader :enrollment, :attempt

  def opportunity
    enrollment.opportunity
  end

  def automation_enabled?
    ScanSolo::AiAgentConfig.published_for(opportunity.account)&.enabled || false
  end

  def template_available?
    channel = opportunity.conversation.inbox.channel
    return true unless channel.is_a?(Channel::Whatsapp)

    Array(channel.message_templates).any? do |template|
      template['name'] == attempt.template_reference && template['status'].to_s.casecmp('approved').zero?
    end
  end
end
