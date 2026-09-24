# frozen_string_literal: true

require 'rails_helper'

# RF-34: ScanSolo only ever sends WhatsApp messages through the native
# `conversation.messages.create!` + Whatsapp::SendOnWhatsappService path --
# no HTTP client to Meta and no Evolution integration under app/**/scan_solo.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ScanSolo sends WhatsApp only through the native path' do
  let(:scansolo_files) { Dir.glob(Rails.root.join('app/**/scan_solo/**/*.{rb,jbuilder}')) }

  it 'has ScanSolo files to check' do
    expect(scansolo_files).not_to be_empty
  end

  it 'never references the Meta Graph API or Evolution in any app/**/scan_solo file' do
    offending = scansolo_files.select { |path| File.read(path).match?(/graph\.facebook\.com|evolution/i) }

    expect(offending).to be_empty, "found Meta/Evolution references in: #{offending.join(', ')}"
  end
end
# rubocop:enable RSpec/DescribeClass
