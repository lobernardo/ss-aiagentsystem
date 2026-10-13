# RF-03 / RF-04 / RF-07..RF-12 / RF-14 / RF-24 / CT-07 / RNF-02: generates the
# proposal PDF of a version locally — the account's active `.docx` template
# rendered with the CT-03 values and converted by Gotenberg — and applies the
# result through ScanSolo::Proposal::CallbackHandler, the sole writer of the
# version's generate result.
#
# Each run first rechecks that the version is still the open generation of
# this correlation id (RF-03); otherwise it ends with no effect. Gotenberg and
# the blob upload run outside any open transaction; under the version's lock
# there is only the recheck, the attach of the uploaded blob and the result.
# A run that loses the recheck purges its blob, so a document attached by
# another generation is never replaced and no orphan blob is left.
#
# GotenbergUnavailable propagates to the job's retry (RF-11); `exhausted!`
# applies `provider_unavailable` once the attempts are over. Qualification data
# never fails the generation (RF-24).
class ScanSolo::Proposal::LocalGenerationService
  RENDER_FAILED = 'template_render_failed'.freeze
  PDF_CONTENT_TYPE = 'application/pdf'.freeze
  CURRENCY = 'BRL'.freeze
  VALIDITY_DAYS = 90

  def self.call(proposal_version_id:, correlation_id:)
    new(proposal_version_id: proposal_version_id, correlation_id: correlation_id).call
  end

  def self.exhausted!(proposal_version_id:, correlation_id:)
    ScanSolo::Proposal::CallbackHandler.apply_generate_result!(
      proposal_version: ScanSolo::ProposalVersion.find(proposal_version_id), correlation_id: correlation_id, success: false,
      failure_reason: 'provider_unavailable', cause: 'conversion'
    )
  end

  def initialize(proposal_version_id:, correlation_id:)
    @proposal_version = ScanSolo::ProposalVersion.find_by(id: proposal_version_id)
    @correlation_id = correlation_id
  end

  def call
    return unless open_generation?

    generate!
  end

  private

  attr_reader :proposal_version, :correlation_id

  def generate!
    template = ScanSolo::ProposalTemplate.active_for(proposal_version.proposal.opportunity.account)
    return fail!('template_unavailable', 'template') unless template
    return fail!(RENDER_FAILED, 'template') if proposal_version.quote_request&.commercial.blank?

    attach!(convert!(template), template)
  rescue CustomExceptions::ScanSolo::GotenbergUnavailable
    raise
  rescue CustomExceptions::ScanSolo::ProposalRenderFailed => e
    fail!(RENDER_FAILED, 'template', e.placeholders.presence)
  rescue CustomExceptions::ScanSolo::GotenbergRejected
    fail!('provider_rejected', 'conversion')
  rescue CustomExceptions::ScanSolo::GotenbergInvalidPdf
    fail!(RENDER_FAILED, 'conversion')
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    @blob&.purge
    fail!(RENDER_FAILED, 'exception')
  end

  # RF-03: still `generating` under this correlation id, with no result applied
  # and no document attached.
  def open_generation?
    proposal_version.present? && proposal_version.generating? && proposal_version.generate_correlation_id == correlation_id &&
      proposal_version.generate_callback_applied_at.nil? && !proposal_version.document.attached?
  end

  # RF-05..RF-09: the rendered `.docx` converted by Gotenberg, outside any transaction.
  def convert!(template)
    docx = ScanSolo::Proposal::TemplateRenderer.call(
      template_bytes: template.file.open(&:read),
      values: ScanSolo::Proposal::TemplateValues.call(proposal_version: proposal_version, generated_at: Time.current)
    )
    ScanSolo::Proposal::GotenbergClient.convert!(docx: docx, filename: "#{proposal_version.proposal_number}.docx")
  end

  # RF-10: upload first, then recheck, attach and apply under the lock.
  def attach!(pdf, template)
    @blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(pdf), filename: "#{proposal_version.proposal_number}.pdf", content_type: PDF_CONTENT_TYPE
    )
    applied = proposal_version.with_lock do
      next false unless open_generation?

      proposal_version.document.attach(@blob)
      succeed!(Digest::SHA256.hexdigest(pdf), template)
      true
    end
    @blob.purge unless applied
  end

  def succeed!(artifact_sha256, template)
    ScanSolo::Proposal::CallbackHandler.apply_generate_result!(
      proposal_version: proposal_version, correlation_id: correlation_id, success: true,
      value: BigDecimal(proposal_version.quote_request.commercial['total_value'].to_s), currency: CURRENCY, artifact_url: nil,
      artifact_sha256: artifact_sha256, template_version: template.template_version,
      valid_until: Time.use_zone(ScanSolo::Cadence::SendingWindow::ZONE) { Time.zone.today + VALIDITY_DAYS }
    )
  end

  def fail!(reason, cause, placeholders = nil)
    ScanSolo::Proposal::CallbackHandler.apply_generate_result!(
      proposal_version: proposal_version, correlation_id: correlation_id, success: false, failure_reason: reason, cause: cause,
      placeholders: placeholders
    )
  end
end
