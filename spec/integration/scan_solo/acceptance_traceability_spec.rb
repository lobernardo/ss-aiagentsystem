# frozen_string_literal: true

require 'rails_helper'

# T77 / RF-92: verifies docs/architecture/SCANSOLO_ACCEPTANCE_TRACEABILITY.md
# maps every description Section 20 acceptance-outcome item (1-19) to at
# least one real, existing automated spec file. This spec does not re-invoke
# rspec on each referenced file (that would race the transactional test
# database this very example runs inside) -- instead it proves the matrix is
# not aspirational: every path it lists exists and is a real RSpec example
# group, and the whole matrix's "passes" claim holds because
# scripts/ralph-test.sh already runs every one of those files inside the same
# suite invocation as this gate.
RSpec.describe 'ScanSolo Section 20 acceptance traceability matrix' do # rubocop:disable RSpec/DescribeClass
  let(:doc_path) { Rails.root.join('docs/architecture/SCANSOLO_ACCEPTANCE_TRACEABILITY.md') }
  let(:doc_content) { File.read(doc_path) }

  it 'exists' do
    expect(File.exist?(doc_path)).to be true
  end

  it 'has a numbered row for every item 1-19' do
    (1..19).each do |item|
      expect(doc_content).to match(/^\|\s*#{item}\s*\|/), "expected a matrix row for item #{item}"
    end
  end

  it 'does not include a row for item 20 (deployment is out of RF-92 scope)' do
    expect(doc_content).not_to match(/^\|\s*20\s*\|/)
  end

  describe 'every referenced spec file' do
    def referenced_spec_paths(content)
      content.scan(%r{`(spec/[\w./-]+_spec\.rb)`}).flatten.uniq
    end

    it 'lists at least one spec per item and every listed file exists on disk' do
      paths = referenced_spec_paths(doc_content)

      expect(paths).not_to be_empty

      paths.each do |path|
        expect(File.exist?(Rails.root.join(path))).to be(true), "matrix references #{path}, which does not exist"
      end
    end

    it 'only references files that are genuine RSpec example groups' do
      referenced_spec_paths(doc_content).each do |path|
        contents = File.read(Rails.root.join(path))
        expect(contents).to match(/RSpec\.describe/), "#{path} is referenced but is not an RSpec.describe file"
      end
    end

    it 'references the capstone integration suite for every item' do
      expect(referenced_spec_paths(doc_content)).to include('spec/integration/scan_solo/full_test_mode_spec.rb')
    end
  end

  # scansolo-operacao-centralizada T33: every RF/UI id of the feature SPEC has
  # a matrix row; RF-48..RF-52 are Make operational requirements, every other
  # row points to existing Ruby or Vitest spec files.
  describe 'operação centralizada section' do
    let(:spec_ids) do
      File.read(Rails.root.join('.spec/features/scansolo-operacao-centralizada/SPEC.md')).scan(/^- ((?:RF|UI)-\d+) \[/).flatten
    end
    let(:operational_ids) { %w[RF-48 RF-49 RF-50 RF-51 RF-52] }
    let(:rows) do
      doc_content.split('## Operação centralizada').last.scan(/^\|\s*((?:RF|UI)-\d+)\s*\|[^|]*\|([^\n]*)\|$/).to_h
    end

    it 'has a row for every RF and UI id of the feature SPEC' do
      expect(spec_ids.size).to eq(63)
      expect(rows.keys).to match_array(spec_ids)
    end

    it 'points every non-operational row to existing spec files' do
      rows.except(*operational_ids).each do |id, tests|
        paths = tests.scan(%r{`((?:spec|app/javascript)/[\w./-]+(?:_spec\.rb|\.spec\.js))`}).flatten

        expect(paths).not_to be_empty, "#{id} has no automated test"
        paths.each { |path| expect(File.exist?(Rails.root.join(path))).to be(true), "#{id} references #{path}, which does not exist" }
      end
    end

    it 'marks only the Make requirements as operational' do
      expect(rows.select { |_id, tests| tests.include?('operacional (Make)') }.keys).to match_array(operational_ids)
    end

    it 'references the end-to-end and legacy compatibility suites' do
      expect(doc_content).to include('`spec/integration/scan_solo/operacao_centralizada_spec.rb`',
                                     '`spec/integration/scan_solo/legacy_compatibility_spec.rb`')
    end
  end
end
