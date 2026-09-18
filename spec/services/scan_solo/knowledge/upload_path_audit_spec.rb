# frozen_string_literal: true

require 'rails_helper'

# RF-90: knowledge-base attachment uploads route through the existing native
# attachment storage/validation mechanism (ActiveStorage), never a parallel
# unvalidated upload path. Cross-cutting audit rather than a spec for a
# single class -- it fails the moment any file under app/**/scan_solo/**
# introduces a raw file-write or storage-client call outside ActiveStorage.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ScanSolo attachment upload path reuse audit' do
  def scansolo_app_files
    Dir.glob(Rails.root.join('app/**/scan_solo/**/*.rb'))
  end

  def relative_to_root(file)
    Pathname.new(file).relative_path_from(Rails.root).to_s
  end

  # Any of these would be a parallel, unvalidated file-write/storage path
  # bypassing ActiveStorage's own validation (RF-90).
  forbidden_patterns = {
    /\bFile\.write\b/ => 'File.write',
    /\bIO\.write\b/ => 'IO.write',
    /\bFileUtils\.(?:cp|mv|touch)\b/ => 'FileUtils file mutation',
    /\bTempfile\.new\b/ => 'Tempfile.new',
    /\bAws::S3::(?:Client|Bucket|Resource|Object)\b/ => 'raw Aws::S3 client'
  }

  it 'finds at least the Knowledge source model and its controller so the scan is exercising real files' do
    relative = scansolo_app_files.map { |file| relative_to_root(file) }

    expect(relative).to include('app/models/scan_solo/knowledge_source.rb')
    expect(relative).to include('app/controllers/api/v1/accounts/scan_solo/knowledge/sources_controller.rb')
  end

  it 'introduces no raw file-write or storage-client call outside ActiveStorage under app/**/scan_solo/**' do
    offenders = scansolo_app_files.each_with_object({}) do |file, memo|
      source = File.read(file)
      hits = forbidden_patterns.select { |pattern, _label| source.match?(pattern) }.values

      memo[file] = hits if hits.any?
    end

    expect(offenders).to be_empty, "forbidden raw upload call(s) found: #{offenders.inspect}"
  end

  it 'declares the document upload attachment through ActiveStorage on ScanSolo::KnowledgeSource, not a bespoke column' do
    expect(ScanSolo::KnowledgeSource.new).to respond_to(:file)
    expect(ScanSolo::KnowledgeSource.reflect_on_attachment(:file)).to be_present
  end

  it 'is the only ScanSolo model declaring an ActiveStorage attachment, and it is the only .attach( call in the layer' do
    model_files = Dir.glob(Rails.root.join('app/models/scan_solo/**/*.rb'))
    attaching_models = model_files.select { |file| File.read(file).match?(/has_one_attached|has_many_attached/) }

    expect(attaching_models.map { |file| relative_to_root(file) })
      .to eq(['app/models/scan_solo/knowledge_source.rb'])

    attach_call_sites = scansolo_app_files.each_with_object({}) do |file, memo|
      count = File.read(file).scan('.attach(').size
      memo[file] = count if count.positive?
    end

    expect(attach_call_sites.keys.map { |file| relative_to_root(file) })
      .to eq(['app/controllers/api/v1/accounts/scan_solo/knowledge/sources_controller.rb'])
  end
end
# rubocop:enable RSpec/DescribeClass
