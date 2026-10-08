# RF-08 / RF-11 / RF-12 / RF-14 / RF-17 / CT-06: delivers an approved proposal
# to the lead by e-mail, through the published quote inbox: To = the contact's
# e-mail, CC = the published `quote_recipient_email`, the PDF stored before
# approval attached. Make is never called here (0 `MakeRequest`), and nothing
# goes over WhatsApp -- the short notice only follows `sent` (LeadNoticeService).
#
# The version is claimed under its row lock (`approved` and never claimed, or
# `failed` after an approval on an explicit redelivery, RF-15 a), so two jobs
# send one e-mail (RNF-02). The lead's proposal thread is one per opportunity
# (`proposal.email_conversation`, marker `proposal_delivery`), opened under the
# Proposal row lock on the 1st delivery and reused by later versions. The
# message is created outside any open transaction (RNF-01) and becomes the
# version's `sent_message`; `sent` waits for its native `source_id` (RF-13).
#
# A missing/invalid lead e-mail (`lead_email_missing`), a missing stored PDF or
# an exception while creating the message (`email_delivery_failed`) fails the
# version with 1 `proposal.delivery_failed` audit, keeping value, artifact_url
# and the stored PDF; the stage never moves here.
class ScanSolo::Proposal::DeliveryService
  THREAD_MARKER = 'proposal_delivery'.freeze
  ORIGIN = 'proposal_email'.freeze
  LEAD_EMAIL_MISSING = 'lead_email_missing'.freeze
  EMAIL_DELIVERY_FAILED = 'email_delivery_failed'.freeze

  def self.call(proposal_version:, redeliver: false)
    new(proposal_version: proposal_version, redeliver: redeliver).call
  end

  def initialize(proposal_version:, redeliver:)
    @proposal_version = proposal_version
    @redeliver = redeliver
  end

  def call
    raise CustomExceptions::ScanSolo::DeliveryInsideTransaction if ActiveRecord::Base.connection.current_transaction.joinable?
    return unless claim!
    return fail!(LEAD_EMAIL_MISSING) unless opportunity.lead_email_valid?
    return fail!(EMAIL_DELIVERY_FAILED) unless proposal_version.document.attached?

    settings = ScanSolo::Quote::Mailbox.resolve!(opportunity.account)
    email = ScanSolo::Quote::EmailComposer.lead_proposal(proposal_version: proposal_version)
    deliver!(email_conversation!(settings.inbox, email.subject), settings.recipient, email)
  end

  private

  attr_reader :proposal_version, :redeliver

  def claim!
    proposal_version.with_lock do
      claimable = if redeliver
                    proposal_version.failed? && proposal_version.approved_at.present?
                  else
                    proposal_version.approved? && proposal_version.sent_message_id.nil? && proposal_version.send_requested_at.nil?
                  end
      next false unless claimable

      proposal_version.update!(status: :approved, failure_reason: nil, send_requested_at: Time.current)
    end
  end

  def email_conversation!(inbox, subject)
    proposal = proposal_version.proposal
    proposal.with_lock do
      proposal.email_conversation ||
        ScanSolo::Quote::EmailThread.open!(inbox: inbox, recipient: opportunity.contact.email, subject: subject, marker: THREAD_MARKER)
                                    .tap { |conversation| proposal.update!(email_conversation: conversation) }
    end
  end

  def deliver!(conversation, commercial_recipient, email)
    message = ScanSolo::Quote::EmailThread.post!(
      conversation: conversation, recipient: opportunity.contact.email, cc: [commercial_recipient], email: email,
      attachments: [proposal_version.document.blob],
      additional_attributes: { 'scansolo_origin' => ORIGIN, 'scansolo_proposal_version_id' => proposal_version.id }
    )
    proposal_version.update!(sent_message: message)
  rescue StandardError => e
    Rails.logger.error("[ScanSolo] proposal e-mail delivery failed for version #{proposal_version.id}: #{e.class}: #{e.message}")
    fail!(EMAIL_DELIVERY_FAILED)
  end

  def fail!(reason)
    proposal_version.update!(status: :failed, failure_reason: reason)
    ScanSolo::AuditLogger.record!(
      subject: opportunity, event_type: 'proposal.delivery_failed', correlation_id: proposal_version.audit_correlation_id,
      payload: { proposal_version_id: proposal_version.id, reason: reason }
    )
  end

  def opportunity
    proposal_version.proposal.opportunity
  end
end
