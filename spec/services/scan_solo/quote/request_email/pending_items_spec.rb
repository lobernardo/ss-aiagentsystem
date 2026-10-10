# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Quote::RequestEmail::PendingItems do
  let(:fixed_labels) { (1..8).map { |index| I18n.t("scan_solo.quote.request_email.pending_items.#{index}") } }
  let(:georadar) { ScanSolo::Quote::RequestEmail::ServiceLabel.call(tipo_servico: nil, tecnologia: 'GPR') }
  let(:planta) { { 'name' => 'planta-executiva.pdf', 'file_type' => 'file' } }
  let(:all_informed) do
    {
      'area' => '2 ha', 'profundidade' => '3 m', 'integracao_seguranca' => 'Sim, 4 h',
      'restricoes_acesso' => 'Portaria', 'prazo_desejado' => '15 dias', 'condicoes_especiais' => 'NF até dia 20'
    }
  end
  let(:all_attachments) { [planta, { 'name' => 'foto.jpg', 'file_type' => 'image' }, { 'name' => 'area.KMZ', 'file_type' => 'file' }] }

  it 'lists the 8 fixed items in CT-07 order for the CT-01 example (RF-08 AC)' do
    items = described_class.call(missing_labels: [], service: georadar, values: { 'empresa' => 'AMAGGI' }, attachments: [planta])

    expect(items).to eq(fixed_labels)
  end

  it 'is empty when everything is informed' do
    expect(described_class.call(missing_labels: [], service: georadar, values: all_informed, attachments: all_attachments)).to eq([])
  end

  it 'accepts the alternative sources of items 1, 4 and 5' do
    values = all_informed.except('area', 'restricoes_acesso', 'prazo_desejado')
                         .merge('metragem' => '200 m', 'documentacoes_necessarias' => 'ASO', 'data_desejada' => '20/11')

    expect(described_class.call(missing_labels: [], service: georadar, values: values, attachments: all_attachments)).to eq([])
  end

  it 'keeps item 8 when only observacoes_tecnicas is filled' do
    values = all_informed.except('condicoes_especiais').merge('observacoes_tecnicas' => 'Piso de concreto')

    expect(described_class.call(missing_labels: [], service: georadar, values: values, attachments: all_attachments)).to eq([fixed_labels[7]])
  end

  it 'appends missing config labels and Tipo de serviço when no service was informed, without repetition' do
    not_informed = ScanSolo::Quote::RequestEmail::ServiceLabel.call(tipo_servico: '', tecnologia: '')
    missing = ['Cidade / UF', fixed_labels[1], 'Cidade / UF']

    items = described_class.call(missing_labels: missing, service: not_informed, values: all_informed.except('profundidade'),
                                 attachments: all_attachments)

    expect(items).to eq([fixed_labels[1], 'Cidade / UF', 'Tipo de serviço'])
  end

  it 'does not repeat Tipo de serviço when it is already a missing config label' do
    not_informed = ScanSolo::Quote::RequestEmail::ServiceLabel.call(tipo_servico: nil, tecnologia: nil)

    items = described_class.call(missing_labels: ['Tipo de serviço'], service: not_informed, values: all_informed,
                                 attachments: all_attachments)

    expect(items).to eq(['Tipo de serviço'])
  end
end
