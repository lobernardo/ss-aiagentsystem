require 'rails_helper'

RSpec.describe ScanSolo::LeadState do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) { ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation) }
  let(:state) { described_class.create!(opportunity: opportunity) }

  it 'persists one state per opportunity with empty data and qualification in progress' do
    expect(state.reload).to have_attributes(intent: nil, next_action: nil, fields: {}, authorized_actions: [], qualification_status: 'em_andamento')
    expect(opportunity.reload.lead_state).to eq(state)
    expect(described_class.new(opportunity: opportunity)).not_to be_valid
  end

  it 'requires an opportunity' do
    expect(described_class.new).not_to be_valid
  end

  it 'defines and persists the qualification enum' do
    expect(described_class.qualification_statuses).to eq('em_andamento' => 0, 'concluida' => 1)
    state.concluida!
    expect(state.reload).to be_concluida
    expect { state.qualification_status = 'invalid' }.to raise_error(ArgumentError)
  end

  it 'accepts exactly the ten intentions and nil' do
    intents = %w[orcamento avaliacao_tecnica convite_cotacao envio_documentos duvida verificar_capacidade localizar_rede visita acompanhar_proposta
                 outro]
    expect(described_class::INTENTS).to eq(intents)
    [*intents, nil].each do |intent|
      state.intent = intent
      expect(state).to be_valid
    end
    state.intent = 'invalid'
    expect(state).not_to be_valid
  end

  it 'accepts exactly the five next actions and nil' do
    actions = %w[proposta avaliacao_tecnica solicitar_documentos atendimento_humano aguardar_cliente]
    expect(described_class::NEXT_ACTIONS).to eq(actions)
    [*actions, nil].each do |action|
      state.next_action = action
      expect(state).to be_valid
    end
    state.next_action = 'invalid'
    expect(state).not_to be_valid
  end

  it 'defines all eleven default next actions from RF-15' do
    expect(described_class::DEFAULT_NEXT_ACTION_BY_INTENT).to eq(
      'orcamento' => 'proposta', 'convite_cotacao' => 'proposta',
      'avaliacao_tecnica' => 'avaliacao_tecnica', 'visita' => 'avaliacao_tecnica', 'localizar_rede' => 'avaliacao_tecnica',
      'envio_documentos' => 'solicitar_documentos', 'acompanhar_proposta' => 'aguardar_cliente',
      'duvida' => 'aguardar_cliente', 'verificar_capacidade' => 'aguardar_cliente', 'outro' => 'aguardar_cliente', nil => 'aguardar_cliente'
    )
    expect(described_class::FIELD_STATUSES).to eq(%w[confirmado inferido faltante])
  end
end
