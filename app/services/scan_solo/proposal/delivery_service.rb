# RF-29 / RF-32 / CT-09 (b): delivers a generated proposal to the lead over
# WhatsApp, with the PDF stored in Chatwoot's ActiveStorage as the template's
# document header. Make only generates; Chatwoot sends -- no `proposal.send`,
# no ApproveService and no `require_proposal_approval` check (RF-28).
#
# The version is claimed under its row lock (`generated` and never claimed,
# or `failed` on an explicit redelivery -- CT-10), so two jobs send one template
# (RNF-02). Download and message creation run after that short transaction,
# never inside one (RNF-01). A redelivery reuses the stored PDF and only downloads
# it again when it is missing.
#
# A failed download (`artifact_download_failed`), a blocked template
# (`guard.reason`) or a message born `failed` (`external_error`) fails the
# version with 1 `proposal.delivery_failed` audit, keeping value,
# artifact_url and the stored PDF; the stage never moves here (RF-33).
class ScanSolo::Proposal::DeliveryService
  STAGE_SLOT = 'proposta_enviada'.freeze
  DOWNLOAD_FAILED = 'artifact_download_failed'.freeze

  def self.call(proposal_version:, redeliver: false)
    new(proposal_version: proposal_version, redeliver: redeliver).call
  end

  def initialize(proposal_version:, redeliver:)
    @proposal_version = proposal_version
    @redeliver = redeliver
  end

  def call
    return unless claim!
    return fail!(DOWNLOAD_FAILED) unless store_document

    template = ScanSolo::Messaging::TemplateResolver.call(
      account: opportunity.account, stage: STAGE_SLOT, step: nil, opportunity: opportunity,
      document: { url: proposal_version.document_url, name: document_name }
    )
    guard = ScanSolo::Cadence::TemplateAvailabilityGuard.check(inbox: opportunity.conversation.inbox, template: template)
    return fail!(guard.reason) if guard.blocked?

    send_template!(template)
  end

  private

  attr_reader :proposal_version, :redeliver

  def send_template!(template)
    message = ScanSolo::Messaging::NativeTemplateSender.call(
      conversation: opportunity.conversation, template_reference: template.name, origin: 'proposal', template_params: template.sender_params
    ).message
    proposal_version.update!(sent_message: message)
    fail!(message.external_error.presence || 'failed') if message.failed?
  end

  def claim!
    proposal_version.with_lock do
      claimable = redeliver ? proposal_version.failed? : proposal_version.generated? && proposal_version.send_requested_at.nil?
      next false unless claimable

      proposal_version.update!(status: :generated, failure_reason: nil, send_requested_at: Time.current)
    end
  end

  def store_document
    return true if proposal_version.document.attached?

    SafeFetch.fetch(proposal_version.artifact_url, allowed_content_type_prefixes: [], allowed_content_types: ['application/pdf']) do |result|
      proposal_version.document.attach(io: result.tempfile, filename: document_name, content_type: 'application/pdf')
    end
    true
  rescue SafeFetch::Error
    false
  end

  def fail!(reason)
    proposal_version.update!(status: :failed, failure_reason: reason)
    ScanSolo::AuditLogger.record!(
      subject: opportunity, event_type: 'proposal.delivery_failed', correlation_id: proposal_version.audit_correlation_id,
      payload: { proposal_version_id: proposal_version.id, reason: reason }
    )
  end

  def document_name
    "#{proposal_version.proposal_number}.pdf"
  end

  def opportunity
    proposal_version.proposal.opportunity
  end
end
