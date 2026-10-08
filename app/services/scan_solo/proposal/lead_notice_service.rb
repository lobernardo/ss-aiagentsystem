# RF-11 / RF-12 / RF-14 / CT-07: once the proposal e-mail is confirmed and the
# version is `sent` (RF-13), sends the lead 1 short WhatsApp notice ("proposta
# enviada para seu e-mail") on the opportunity's conversation -- slot
# `proposta_aviso_email`, origin `proposal_notice`, no document header and no
# link. Under the version's row lock it only runs for a `sent` version whose
# notice is missing or `failed`, so a repeated reconciliation sends no 2nd
# notice and a redelivered e-mail (RF-15 a) gets one only if none was accepted
# (RNF-02). A blocked template keeps the version `sent` and records
# `notice_failure_reason` plus 1 `proposal.lead_notice_failed` audit. The
# native transport only runs after the creation commits (Message#send_reply).
class ScanSolo::Proposal::LeadNoticeService
  SLOT = 'proposta_aviso_email'.freeze
  ORIGIN = 'proposal_notice'.freeze

  def self.call(proposal_version:)
    new(proposal_version: proposal_version).call
  end

  def initialize(proposal_version:)
    @proposal_version = proposal_version
  end

  def call
    proposal_version.with_lock do
      next unless proposal_version.sent?
      next unless proposal_version.notice_message.nil? || proposal_version.notice_message.failed?

      template = ScanSolo::Messaging::TemplateResolver.call(account: opportunity.account, stage: SLOT, step: nil, opportunity: opportunity)
      guard = ScanSolo::Cadence::TemplateAvailabilityGuard.check(inbox: opportunity.conversation.inbox, template: template)
      next block!(guard.reason) if guard.blocked?

      send_notice!(template)
    end
  end

  private

  attr_reader :proposal_version

  def send_notice!(template)
    message = ScanSolo::Messaging::NativeTemplateSender.call(
      conversation: opportunity.conversation, template_reference: template.name, origin: ORIGIN, template_params: template.sender_params
    ).message
    proposal_version.update!(notice_message: message, notice_failure_reason: nil)
  end

  def block!(reason)
    proposal_version.update!(notice_failure_reason: reason)
    ScanSolo::AuditLogger.record!(
      subject: opportunity, event_type: 'proposal.lead_notice_failed', correlation_id: proposal_version.audit_correlation_id,
      payload: { proposal_version_id: proposal_version.id, reason: reason }
    )
  end

  def opportunity
    proposal_version.proposal.opportunity
  end
end
