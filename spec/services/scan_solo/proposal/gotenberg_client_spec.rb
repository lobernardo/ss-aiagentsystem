# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Proposal::GotenbergClient do
  subject(:convert!) { described_class.convert!(docx: docx, filename: 'SS-2026-000123.docx') }

  let(:convert_url) { 'http://gotenberg.test:3000/forms/libreoffice/convert' }
  let(:docx) { scan_solo_docx_valid }
  let(:pdf) { file_fixture('sample.pdf').binread }

  around do |example|
    with_modified_env(SCANSOLO_GOTENBERG_URL: 'http://gotenberg.test:3000') { example.run }
  end

  it 'returns the PDF bytes and posts 1 multipart file in the `files` field with the given name (CT-04)' do
    stub_request(:post, convert_url).to_return(status: 200, body: pdf)

    expect(convert!).to eq(pdf)
    expect(
      a_request(:post, convert_url).with do |request|
        request.headers['Content-Type'].start_with?('multipart/form-data') &&
          request.body.scan('Content-Disposition: form-data').size == 1 &&
          request.body.include?('name="files"; filename="SS-2026-000123.docx"')
      end
    ).to have_been_made.once
  end

  it 'raises GotenbergInvalidPdf for a 200 that is not a PDF (RF-09)' do
    stub_request(:post, convert_url).to_return(status: 200, body: '<html>erro</html>')

    expect { convert! }.to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::ScanSolo::GotenbergInvalidPdf') })
  end

  it 'raises GotenbergInvalidPdf for a 200 starting with %PDF that PDF::Reader cannot open (RF-09)' do
    stub_request(:post, convert_url).to_return(status: 200, body: '%PDF-1.4 truncado')

    expect { convert! }.to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::ScanSolo::GotenbergInvalidPdf') })
  end

  it 'raises GotenbergUnavailable for a 5xx, with only the status in the message (RF-11, RNF-04)' do
    stub_request(:post, convert_url).to_return(status: 503, body: 'corpo do erro')

    expect { convert! }.to(raise_error do |error|
      expect(error.class.name).to eq('CustomExceptions::ScanSolo::GotenbergUnavailable')
      expect(error.message).to eq('HTTP 503')
    end)
  end

  it 'raises GotenbergUnavailable on timeout (RF-11, RNF-03)' do
    stub_request(:post, convert_url).to_timeout

    expect { convert! }.to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::ScanSolo::GotenbergUnavailable') })
  end

  it 'raises GotenbergUnavailable on a refused connection (RF-11)' do
    stub_request(:post, convert_url).to_raise(Errno::ECONNREFUSED)

    expect { convert! }.to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::ScanSolo::GotenbergUnavailable') })
  end

  it 'raises GotenbergRejected for a 4xx (RF-11)' do
    stub_request(:post, convert_url).to_return(status: 400, body: 'corpo do erro')

    expect { convert! }.to(raise_error do |error|
      expect(error.class.name).to eq('CustomExceptions::ScanSolo::GotenbergRejected')
      expect(error.message).to eq('HTTP 400')
    end)
  end

  it 'uses explicit open and read timeouts (RNF-03)' do
    stub_request(:post, convert_url).to_return(status: 200, body: pdf)
    allow(RestClient::Request).to receive(:execute).and_call_original

    convert!

    expect(RestClient::Request).to have_received(:execute).with(hash_including(open_timeout: 5, read_timeout: 60))
  end

  it 'raises DeliveryInsideTransaction inside an open transaction and makes 0 requests (RNF-02)' do
    stub_request(:post, convert_url).to_return(status: 200, body: pdf)

    expect { ActiveRecord::Base.transaction { convert! } }
      .to(raise_error { |error| expect(error.class.name).to eq('CustomExceptions::ScanSolo::DeliveryInsideTransaction') })
    expect(a_request(:post, convert_url)).not_to have_been_made
  end
end
