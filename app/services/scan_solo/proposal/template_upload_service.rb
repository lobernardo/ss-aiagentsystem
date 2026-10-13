# RF-17, CT-05, CT-07: makes an uploaded `.docx` the account's active proposal
# template. The file is validated (TemplateDocument#validate!) before any
# write, so an invalid file leaves no record, blob nor audit event. In one
# transaction the previous active template becomes inactive (kept as
# history), the new one is created active with its SHA-256 and uploader, and
# `proposal_template.uploaded` is audited.
class ScanSolo::Proposal::TemplateUploadService
  CONTENT_TYPE = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'.freeze

  def self.call(account:, actor:, file:)
    new(account: account, actor: actor, file: file).call
  end

  def initialize(account:, actor:, file:)
    @account = account
    @actor = actor
    @file = file
  end

  def call
    bytes = file.read
    ScanSolo::Proposal::TemplateDocument.new(bytes).validate!
    sha256 = Digest::SHA256.hexdigest(bytes)

    ActiveRecord::Base.transaction do
      previous = ScanSolo::ProposalTemplate.active.lock.find_by(account: account)
      previous&.update!(active: false)
      template = create_template!(bytes, sha256)
      audit!(template, previous)
      template
    end
  end

  private

  attr_reader :account, :actor, :file

  def create_template!(bytes, sha256)
    template = ScanSolo::ProposalTemplate.new(account: account, uploaded_by: actor, filename: file.original_filename,
                                              byte_size: bytes.bytesize, sha256: sha256, active: true)
    template.file.attach(io: StringIO.new(bytes), filename: file.original_filename, content_type: CONTENT_TYPE)
    template.save!
    template
  end

  def audit!(template, previous)
    ScanSolo::AuditLogger.record!(
      subject: template, event_type: 'proposal_template.uploaded', actor: actor, correlation_id: SecureRandom.uuid,
      payload: { template_id: template.id, filename: template.filename, byte_size: template.byte_size, sha256: template.sha256,
                 previous_template_id: previous&.id }
    )
  end
end
