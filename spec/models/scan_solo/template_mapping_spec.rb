require 'rails_helper'

RSpec.describe ScanSolo::TemplateMapping do
  let(:account) { create(:account) }
  let(:mapping) do
    described_class.new(account: account, stage: 'proposta_enviada', step: nil, template_name: 'proposal', language: 'pt_BR')
  end

  it 'accepts the allowlisted sources and rejects contact phone data' do
    mapping.params = [{ source: 'contact_name' }, { source: 'static', value: 'Olá' }]
    expect(mapping).to be_valid

    mapping.params = [{ source: 'phone_number' }]
    expect(mapping).not_to be_valid
  end

  it 'requires a static value and an array of parameter objects' do
    [nil, {}, ['contact_name'], [{ source: 'static' }]].each do |params|
      mapping.params = params
      expect(mapping).not_to be_valid
    end
  end

  it 'reserves a single proposal mapping even when step is null' do
    mapping.save!
    expect(mapping.dup).not_to be_valid
    expect { mapping.dup.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'requires positive cadence steps and known stages' do
    mapping.assign_attributes(stage: 'novo_lead', step: nil)
    expect(mapping).not_to be_valid
    mapping.step = 1
    expect(mapping).to be_valid
    mapping.stage = 'ganho'
    expect(mapping).not_to be_valid
  end

  it 'accepts the CT-09 slots only with a null step' do
    %w[lead_manual_inicial proposta_acompanhamento proposta_aviso_email].each do |slot|
      mapping.assign_attributes(stage: slot, step: nil)
      expect(mapping).to be_valid

      mapping.step = 1
      expect(mapping).not_to be_valid
    end
  end

  it 'keeps the proposal send naming and adds the CT-07 email notice slot' do
    expect(described_class::SINGLE_TEMPLATES['proposta_enviada']).to eq('scansolo_proposal_send')
    expect(described_class::SINGLE_TEMPLATES['proposta_aviso_email']).to eq('scansolo_proposta_aviso_email')
  end
end
