# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Quote::RequestEmail::LocationLinks do
  it 'keeps the first of two points less than 50 m apart (RF-10 AC)' do
    links = described_class.call(
      sources: [
        'https://www.google.com/maps?q=-13.0053596,-55.9400673',
        'https://maps.google.com/?q=-13.00536,-55.94007'
      ]
    )

    expect(links).to eq(['https://www.google.com/maps?q=-13.0053596,-55.9400673'])
  end

  it 'keeps distinct points in order of receipt, normalized to 6-7 decimals' do
    links = described_class.call(
      sources: [
        'https://www.google.com/maps/search/?api=1&query=-13.02336,-55.94007',
        'https://www.google.com/maps?ll=-13.0053596,-55.9400673&z=15'
      ]
    )

    expect(links).to eq(
      [
        'https://www.google.com/maps?q=-13.023360,-55.940070',
        'https://www.google.com/maps?q=-13.0053596,-55.9400673'
      ]
    )
  end

  it 'reads the @lat,lng format' do
    links = described_class.call(sources: ['https://www.google.com/maps/place/Obra/@-13.1,-55.9,17z/data=abc'])

    expect(links).to eq(['https://www.google.com/maps?q=-13.100000,-55.900000'])
  end

  it 'keeps a short map link as is, without HTTP' do
    links = described_class.call(sources: ['https://maps.app.goo.gl/abc', 'https://maps.app.goo.gl/abc'])

    expect(links).to eq(['https://maps.app.goo.gl/abc', 'https://maps.app.goo.gl/abc'])
    expect(a_request(:any, /.*/)).not_to have_been_made
  end

  it 'drops non-https URLs and hosts outside the map pattern' do
    links = described_class.call(
      sources: [
        'http://evil.example/maps?q=1,1',
        'https://evil.example/maps?q=1,1',
        'http://www.google.com/maps?q=-13.0053596,-55.9400673',
        nil
      ]
    )

    expect(links).to eq([])
  end
end
