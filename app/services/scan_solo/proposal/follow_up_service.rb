# RF-31 / CT-09 (c): once a proposal version is really `sent` (RF-30), sends
# exactly 1 "acompanhamento pós-proposta" template through
# NativeTemplateSender (origin `proposal_follow_up`). The version row lock and
# `follow_up_message_id` keep a repeated reconciliation from sending a second
# one (RNF-02); a version that is not `sent` (e.g. `failed`) gets none. A
# blocked template is audited as `proposal.follow_up_blocked`. The native
# transport only runs after the creation commits (Message#send_reply).
class ScanSolo::Proposal::FollowUpService
  SLOT = 'proposta_acompanhamento'.freeze

  def self.call(proposal_version:)
    opportunity = proposal_version.proposal.opportunity

    proposal_version.with_lock do
      next unless proposal_version.sent? && proposal_version.follow_up_message_id.nil?

      template = ScanSolo::Messaging::TemplateResolver.call(account: opportunity.account, stage: SLOT, step: nil, opportunity: opportunity)
      guard = ScanSolo::Cadence::TemplateAvailabilityGuard.check(inbox: opportunity.conversation.inbox, template: template)
      if guard.blocked?
        ScanSolo::AuditLogger.record!(
          subject: opportunity, event_type: 'proposal.follow_up_blocked', correlation_id: proposal_version.audit_correlation_id,
          payload: { proposal_version_id: proposal_version.id, reason: guard.reason }
        )
        next
      end

      message = ScanSolo::Messaging::NativeTemplateSender.call(
        conversation: opportunity.conversation, template_reference: template.name, origin: 'proposal_follow_up',
        template_params: template.sender_params
      ).message
      proposal_version.update!(follow_up_message: message)
    end
  end
end
