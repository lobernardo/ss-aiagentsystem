# frozen_string_literal: true

require 'rails_helper'

# Durable licensing-boundary guardrail (RF-26): no file under any
# app/**/scan_solo/ directory may require, inherit from, or call a
# Captain:: enterprise class.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ScanSolo has no enterprise Captain:: dependency' do
  let(:scansolo_files) { Dir.glob(Rails.root.join('app/**/scan_solo/**/*.rb')) }

  it 'has ScanSolo files to check' do
    expect(scansolo_files).not_to be_empty
  end

  it 'never references Captain:: in any app/**/scan_solo/ file' do
    offending = scansolo_files.select { |path| File.read(path).match?(/\bCaptain::/) }

    expect(offending).to be_empty, "found Captain:: references in: #{offending.join(', ')}"
  end
end
# rubocop:enable RSpec/DescribeClass
