# RF-07/RF-08: the initial WhatsApp template of a manual lead. Runs after
# ScanSolo::Pipeline::ManualLeadService commits (RNF-01) and sends the
# `lead_manual_inicial` slot through the native path
# (ScanSolo::Messaging::NativeTemplateSender) marked `manual_lead`, so the
# listener never treats it as a human takeover and the AI stays `ai_active`.
#
# A template the guard blocks is never sent: the block reason is audited as
# `pipeline.manual_lead_template_blocked` for the opportunity detail (UI-04).
# A native delivery failure is audited later by
# ScanSolo::Messaging::DeliveryReconciler. There is no automatic resend.
class ScanSolo::Pipeline::ManualLeadOutreach
  SLOT = 'lead_manual_inicial'.freeze
  ORIGIN = 'manual_lead'.freeze
  BLOCKED_EVENT = 'pipeline.manual_lead_template_blocked'.freeze

  def self.call(opportunity:)
    conversation = opportunity.conversation
    template = ScanSolo::Messaging::TemplateResolver.call(account: opportunity.account, stage: SLOT, step: nil, opportunity: opportunity)
    guard = ScanSolo::Cadence::TemplateAvailabilityGuard.check(inbox: conversation.inbox, template: template)

    if guard.blocked?
      ScanSolo::AuditLogger.record!(
        subject: opportunity, event_type: BLOCKED_EVENT, correlation_id: SecureRandom.uuid,
        payload: { reason: guard.reason }
      )
      return
    end

    ScanSolo::Messaging::NativeTemplateSender.call(
      conversation: conversation, template_reference: template.name, origin: ORIGIN, template_params: template.sender_params
    )
  end
end
