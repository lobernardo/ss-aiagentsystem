# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Proposal::TemplateValues do
  subject(:values) { described_class.call(proposal_version: version, generated_at: generated_at) }

  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, name: '', email: nil, phone_number: nil, custom_attributes: {}) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end
  let(:commercial) do
    { 'total_value' => '12500.00', 'schedule' => '30 dias', 'scope' => "Sondagem sintética\n3 furos", 'payment_terms' => '50% na assinatura',
      'notes' => nil }
  end
  let(:quote_request) do
    ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid, status: :replied,
                                   replied_at: Time.current, commercial: commercial, created_at: Time.utc(2026, 10, 13, 3))
  end
  let(:version) do
    ScanSolo::Proposal.create!(opportunity: opportunity).versions.create!(generate_correlation_id: SecureRandom.uuid, quote_request: quote_request)
  end
  let(:generated_at) { Time.utc(2026, 11, 2, 2, 30) }
  let(:state_fields) { {} }

  before { opportunity.lead_state.update!(fields: state_fields) }

  it 'returns exactly the 16 CT-03 placeholders' do
    expect(values.keys).to match_array(ScanSolo::Proposal::TemplateDocument::PLACEHOLDERS)
  end

  it 'formats the proposal number, the pt-BR dates in São Paulo and the commercial data (D-01)' do
    expect(values).to include(
      'NUMERO_PROPOSTA' => version.proposal_number,
      'DATA_PROPOSTA' => '1 de novembro de 2026',
      'DATA_SOLICITACAO' => '13 de outubro de 2026',
      'DESCRICAO_ESCOPO' => "Sondagem sintética\n3 furos",
      'PRAZO_CRONOGRAMA' => '30 dias',
      'CONDICOES_PAGAMENTO' => '50% na assinatura',
      'OBSERVACOES_COMERCIAIS' => '',
      'VALOR_NUMERICO' => '12.500,00',
      'VALOR_EXTENSO' => 'doze mil e quinhentos reais'
    )
  end

  it 'writes every absent qualification value as the neutral text and never fails (RF-07, RF-24)' do
    expect(values).to include(
      'NOME_EMPRESA' => 'Não informado', 'NOME_CONTATO' => 'Não informado', 'PROJETO_CLIENTE_FINAL' => 'Não informado',
      'ENDERECO_OBRA' => 'Não informado', 'CIDADE_ESTADO' => 'Não informado', 'RUA_CIDADE_ESTADO' => 'localidade não informada',
      'TRECHO_PROFUNDIDADE' => ''
    )
  end

  it 'does not consult the proposal gate or the completion service (RF-24)' do
    expect_any_instance_of(ScanSolo::Qualification::FieldResolver).not_to receive(:missing_labels) # rubocop:disable RSpec/AnyInstance
    expect_any_instance_of(ScanSolo::Qualification::FieldResolver).not_to receive(:proposal_gate_missing_labels) # rubocop:disable RSpec/AnyInstance
    expect(ScanSolo::LeadState::CompletionService).not_to receive(:call)

    values
  end

  context 'with a nao_informado depth whose words are mirrored on the contact (RF-33 e)' do
    let(:contact) { create(:contact, account: account, name: '', custom_attributes: { 'profundidade' => 'não sei' }) }
    let(:state_fields) { { 'profundidade' => { 'status' => 'nao_informado', 'value' => 'não sei' } } }

    it 'omits the depth excerpt and never prints the lead words' do
      expect(values['TRECHO_PROFUNDIDADE']).to eq('')
      expect(values.values.join(' ')).not_to include('não sei')
    end
  end

  context 'with a confirmed depth' do
    let(:state_fields) { { 'profundidade' => { 'status' => 'confirmado', 'value' => '3 m' } } }

    it 'writes the depth excerpt with the value as recorded' do
      expect(values['TRECHO_PROFUNDIDADE']).to eq(', com foco até 3 m de profundidade')
    end
  end

  context 'with only the intervention depth on the contact' do
    let(:contact) { create(:contact, account: account, name: '', custom_attributes: { 'profundidade_intervencao' => '1,5 m' }) }

    it 'falls back to profundidade_intervencao' do
      expect(values['TRECHO_PROFUNDIDADE']).to eq(', com foco até 1,5 m de profundidade')
    end
  end

  context 'with identification from the lead state and the contact' do
    let(:contact) { create(:contact, account: account, name: 'Contato Sintético', custom_attributes: { 'Empresa' => 'Empresa Sintética' }) }
    let(:state_fields) { { 'cliente_final' => { 'status' => 'inferido', 'value' => 'Unidade Sintética' } } }

    it 'resolves company, contact and final client by precedence' do
      expect(values).to include('NOME_EMPRESA' => 'Empresa Sintética', 'NOME_CONTATO' => 'Contato Sintético',
                                'PROJETO_CLIENTE_FINAL' => 'Unidade Sintética')
    end
  end

  context 'with only the contact name' do
    let(:contact) { create(:contact, account: account, name: 'Contato Sintético') }

    it 'uses the name for company and final client (D-04)' do
      expect(values).to include('NOME_EMPRESA' => 'Contato Sintético', 'PROJETO_CLIENTE_FINAL' => 'Contato Sintético')
    end
  end

  context 'with a nao_informado company mirrored on the contact' do
    let(:contact) { create(:contact, account: account, name: '', custom_attributes: { 'empresa' => 'não tenho' }) }
    let(:state_fields) { { 'empresa' => { 'status' => 'nao_informado', 'value' => 'não tenho' } } }

    it 'treats it as absent without reading the contact' do
      expect(values['NOME_EMPRESA']).to eq('Não informado')
    end
  end

  context 'with address, district and city (CT-03)' do
    let(:state_fields) do
      { 'endereco_obra' => { 'status' => 'confirmado', 'value' => 'Rua Sintética, 100' },
        'bairro' => { 'status' => 'confirmado', 'value' => 'Centro' },
        'cidade_uf' => { 'status' => 'confirmado', 'value' => 'Cuiabá/MT' } }
    end

    it 'appends the district, formats the city with an en dash and joins both' do
      expect(values).to include('ENDERECO_OBRA' => 'Rua Sintética, 100, Centro', 'CIDADE_ESTADO' => 'Cuiabá – MT',
                                'RUA_CIDADE_ESTADO' => 'Rua Sintética, 100, Centro, em Cuiabá – MT')
    end
  end

  context 'with a district already in the address' do
    let(:state_fields) do
      { 'endereco_obra' => { 'status' => 'confirmado', 'value' => 'Rua Sintética, 100 - centro' },
        'bairro' => { 'status' => 'confirmado', 'value' => 'Centro' } }
    end

    it 'does not repeat it and writes only the address location' do
      expect(values).to include('ENDERECO_OBRA' => 'Rua Sintética, 100 - centro', 'RUA_CIDADE_ESTADO' => 'Rua Sintética, 100 - centro',
                                'CIDADE_ESTADO' => 'Não informado')
    end
  end

  context 'with only the district and a city without a valid UF' do
    let(:state_fields) do
      { 'bairro' => { 'status' => 'confirmado', 'value' => 'Centro' }, 'cidade_uf' => { 'status' => 'confirmado', 'value' => 'Cuiabá' } }
    end

    it 'keeps the address absent and the city as is' do
      expect(values).to include('ENDERECO_OBRA' => 'Não informado', 'CIDADE_ESTADO' => 'Cuiabá', 'RUA_CIDADE_ESTADO' => 'Cuiabá')
    end
  end

  context 'with commercial notes' do
    let(:commercial) { super().merge('notes' => 'Mobilização inclusa', 'total_value' => '1234567.8') }

    it 'quotes the notes and formats the amount' do
      expect(values).to include('OBSERVACOES_COMERCIAIS' => 'Mobilização inclusa', 'VALOR_NUMERICO' => '1.234.567,80')
    end
  end
end
