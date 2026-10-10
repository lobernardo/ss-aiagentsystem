# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Quote::RequestEmail::CompanyShortName do
  let(:contact_name) { 'Maria Silva' }

  it 'removes activity and corporate suffixes repeatedly (RF-03 AC)' do
    expect(described_class.call(company: 'AMAGGI Exportação e Importação Ltda.', contact_name: contact_name)).to eq('AMAGGI')
  end

  it 'keeps the full company name when the result is shorter than 2 characters' do
    expect(described_class.call(company: 'ME Ltda.', contact_name: contact_name)).to eq('ME Ltda.')
  end

  it 'removes S.A.' do
    expect(described_class.call(company: 'Construtora Alfa S.A.', contact_name: contact_name)).to eq('Construtora Alfa')
  end

  it 'ignores case and accents' do
    expect(described_class.call(company: 'construtora alfa sa', contact_name: contact_name)).to eq('construtora alfa')
    expect(described_class.call(company: 'AMAGGI EXPORTACAO E IMPORTACAO LTDA', contact_name: contact_name)).to eq('AMAGGI')
    expect(described_class.call(company: 'Silva comercio', contact_name: contact_name)).to eq('Silva')
  end

  it 'only removes whole-word suffixes' do
    expect(described_class.call(company: 'ACME', contact_name: contact_name)).to eq('ACME')
    expect(described_class.call(company: 'Visa', contact_name: contact_name)).to eq('Visa')
  end

  it 'uses the contact name without a company' do
    expect(described_class.call(company: '', contact_name: contact_name)).to eq('Maria Silva')
    expect(described_class.call(company: nil, contact_name: contact_name)).to eq('Maria Silva')
    expect(described_class.call(company: '   ', contact_name: contact_name)).to eq('Maria Silva')
  end
end
