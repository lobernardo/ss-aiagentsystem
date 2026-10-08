# RF-01 / RF-02 / RF-25 / CT-05: after the generate callback commits, stores
# the version's PDF from `artifact_url` in ActiveStorage (`SafeFetch`, only
# `application/pdf`), checks it against Make's `artifact_sha256` when one was
# sent, and posts the approval request e-mail -- PDF attached, link to the
# Proposals screen -- on the quote request's e-mail thread to the published
# `quote_recipient_email`. Nothing is ever sent to the lead here.
#
# The request is claimed under the version's row lock through
# `approval_requested_at`, so a job retry or a repeated download never sends a
# 2nd e-mail (RNF-02). Download and message creation run outside any open
# transaction (RNF-01). A failed download (`artifact_download_failed`) or a
# checksum mismatch (`artifact_checksum_mismatch`) fails the version with 1
# `proposal.delivery_failed` audit and sends nothing; `redownload: true`
# fetches the PDF again for such a version (RF-15 c).
class ScanSolo::Proposal::ApprovalRequestService
  DOWNLOAD_FAILED = 'artifact_download_failed'.freeze
  CHECKSUM_MISMATCH = 'artifact_checksum_mismatch'.freeze
  REDOWNLOAD_REASONS = [DOWNLOAD_FAILED, CHECKSUM_MISMATCH].freeze

  def self.call(proposal_version:, redownload: false)
    new(proposal_version: proposal_version, redownload: redownload).call
  end

  def initialize(proposal_version:, redownload:)
    @proposal_version = proposal_version
    @redownload = redownload
  end

  def call
    raise CustomExceptions::ScanSolo::DeliveryInsideTransaction if ActiveRecord::Base.connection.current_transaction.joinable?
    return unless eligible?
    return fail!(DOWNLOAD_FAILED) unless store_document
    return fail!(CHECKSUM_MISMATCH) unless checksum_matches?

    settings = ScanSolo::Quote::Mailbox.resolve!(opportunity.account)
    return unless claim!

    request_approval!(settings)
  end

  private

  attr_reader :proposal_version, :redownload

  def eligible?
    return proposal_version.failed? && REDOWNLOAD_REASONS.include?(proposal_version.failure_reason) if redownload

    proposal_version.awaiting_approval?
  end

  def store_document
    return true if proposal_version.document.attached? && !redownload

    proposal_version.document.purge if proposal_version.document.attached?
    SafeFetch.fetch(proposal_version.artifact_url, allowed_content_type_prefixes: [], allowed_content_types: ['application/pdf']) do |result|
      proposal_version.document.attach(io: result.tempfile, filename: "#{proposal_version.proposal_number}.pdf", content_type: 'application/pdf')
    end
    true
  rescue SafeFetch::Error
    false
  end

  def checksum_matches?
    return true if proposal_version.artifact_sha256.blank?
    return true if Digest::SHA256.hexdigest(proposal_version.document.download) == proposal_version.artifact_sha256

    proposal_version.document.purge
    false
  end

  def claim!
    proposal_version.with_lock do
      next false if proposal_version.approval_requested_at.present? || !eligible?

      proposal_version.update!(status: :awaiting_approval, failure_reason: nil, approval_requested_at: Time.current)
    end
  end

  def request_approval!(settings)
    message = ScanSolo::Quote::EmailThread.post!(
      conversation: proposal_version.quote_request.email_conversation, recipient: settings.recipient,
      email: ScanSolo::Quote::EmailComposer.approval_request(proposal_version: proposal_version),
      attachments: [proposal_version.document.blob]
    )
    proposal_version.update!(approval_request_message: message)
    audit!('proposal.approval_requested', message_id: message.id)
  end

  def fail!(reason)
    proposal_version.update!(status: :failed, failure_reason: reason)
    audit!('proposal.delivery_failed', reason: reason)
  end

  def audit!(event_type, **payload)
    ScanSolo::AuditLogger.record!(
      subject: opportunity, event_type: event_type, correlation_id: proposal_version.audit_correlation_id,
      payload: { proposal_version_id: proposal_version.id, **payload }
    )
  end

  def opportunity
    proposal_version.proposal.opportunity
  end
end
