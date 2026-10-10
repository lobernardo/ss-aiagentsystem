# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Quote::RequestEmail::ServiceLabel do
  it 'maps a GeoRadar term from tecnologia (RF-04 AC)' do
    result = described_class.call(tipo_servico: nil, tecnologia: 'GPR')

    expect(result.to_h).to eq(label: 'GeoRadar', service_key: 'GeoRadar', informed: true)
  end

  it 'combines terms of both groups, ignoring case and accents' do
    expect(described_class.call(tipo_servico: 'Georadar e pipe locator', tecnologia: nil).label).to eq('GeoRadar + Pipe Locator')
    expect(described_class.call(tipo_servico: 'Varredura', tecnologia: 'LOCALIZADOR DE TUBULACAO').label).to eq('Pipe Locator')
  end

  it 'keeps the free text without a known term, with service_key outro' do
    result = described_class.call(tipo_servico: "Sondagem\r\n  SPT", tecnologia: 'Trado')

    expect(result.to_h).to eq(label: 'Sondagem SPT', service_key: 'outro', informed: true)
  end

  it 'falls back to tecnologia as free text' do
    expect(described_class.call(tipo_servico: '', tecnologia: 'Laser scanner').label).to eq('Laser scanner')
  end

  it 'returns "Serviço não informado" when both are empty' do
    result = described_class.call(tipo_servico: ' ', tecnologia: nil)

    expect(result.to_h).to eq(label: 'Serviço não informado', service_key: 'outro', informed: false)
  end
end
