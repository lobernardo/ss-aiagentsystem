# frozen_string_literal: true

require 'rails_helper'

# RF-69: static verification that no cadence scheduling calculation depends
# on an LLM call -- every offset is a deterministic configuration value.
# No production code lives here; this is a repo-search assertion only.
RSpec.describe 'ScanSolo cadence engine has no LLM-based timing dependency' do
  let(:cadence_files) { Dir.glob(Rails.root.join('app/services/scan_solo/cadence/**/*.rb')) }

  it 'finds the cadence service files to check' do
    expect(cadence_files).not_to be_empty
  end

  it 'contains no reference to Llm:: or ScanSolo::AiAgent in any cadence service' do
    offending = cadence_files.select { |path| File.read(path).match?(/Llm::|ScanSolo::AiAgent\b/) }

    expect(offending).to be_empty, "expected no LLM-timing dependency, found references in: #{offending.join(', ')}"
  end
end
