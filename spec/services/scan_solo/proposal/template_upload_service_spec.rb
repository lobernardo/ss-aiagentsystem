# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Proposal::TemplateUploadService do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:bytes) { scan_solo_docx_valid }
  let(:file) { Rack::Test::UploadedFile.new(StringIO.new(bytes), described_class::CONTENT_TYPE, original_filename: 'proposta-v3.docx') }
  let(:uploaded_events) { ScanSolo::AuditEvent.where(event_type: 'proposal_template.uploaded') }

  def upload(upload_file = file)
    described_class.call(account: account, actor: admin, file: upload_file)
  end

  it 'activates the template with its metadata and audits it (RF-17, CT-07)' do
    template = upload

    expect(template).to have_attributes(account: account, uploaded_by: admin, filename: 'proposta-v3.docx', byte_size: bytes.bytesize,
                                        sha256: Digest::SHA256.hexdigest(bytes), active: true)
    expect(template.file.download).to eq(bytes)
    expect(uploaded_events.sole).to have_attributes(subject: template, actor: admin)
    expect(uploaded_events.sole.payload).to eq(
      'template_id' => template.id, 'filename' => 'proposta-v3.docx', 'byte_size' => bytes.bytesize,
      'sha256' => template.sha256, 'previous_template_id' => nil
    )
  end

  it 'deactivates and keeps the previous active template' do
    previous = upload
    current = upload(Rack::Test::UploadedFile.new(StringIO.new(bytes), described_class::CONTENT_TYPE, original_filename: 'v4.docx'))

    expect(previous.reload).not_to be_active
    expect(ScanSolo::ProposalTemplate.active_for(account)).to eq(current)
    expect(uploaded_events.order(:id).last.payload['previous_template_id']).to eq(previous.id)
  end

  it 'writes nothing for an invalid file' do
    previous = upload
    invalid = Rack::Test::UploadedFile.new(StringIO.new(scan_solo_docx_valid(split: ['VALOR_EXTENSO'])), described_class::CONTENT_TYPE,
                                           original_filename: 'quebrado.docx')

    expect { upload(invalid) }
      .to raise_error(CustomExceptions::ScanSolo::ProposalTemplateInvalid) { |error| expect(error.code).to eq('split_placeholders') }
      .and(not_change(ScanSolo::ProposalTemplate, :count))
      .and(not_change(ActiveStorage::Blob, :count))
      .and(not_change(ScanSolo::AuditEvent, :count))
    expect(ScanSolo::ProposalTemplate.active_for(account)).to eq(previous)
  end
end
