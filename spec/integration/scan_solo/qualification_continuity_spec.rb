# frozen_string_literal: true

require 'rails_helper'

# RF-17 (integration), RF-08, RF-11, RNF-06(6): end-to-end continuity of the
# qualification flow through real turns. Every turn runs the real
# ScanSolo::AiTurn::TurnOrchestrator with ScanSolo::TestMode::MockLlmProvider,
# and assertions are made only on what would reach the provider
# (`MockLlmProvider.last_payload`) and on what the fixture `qualification_field`
# action saved -- never on the mock's reply text.
#
# Lead state RF-08: a field is satisfied only when `confirmado` in the lead
# state, so a name that only exists on the Contact (seeded `inferido`) stays
# in the missing fields.
RSpec.describe 'ScanSolo qualification continuity' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Leonardo', email: nil, custom_attributes: {}) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_contato)
  end
  let(:labels) do
    ['Nome', 'Objetivo do serviço', 'Cidade / UF', 'Endereço da obra', 'Área ou extensão', 'Profundidade de interesse',
     'Prazo desejado', 'Integração de segurança', 'Empresa', 'E-mail']
  end

  before do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente ScanSolo', enabled: true, allowed_inbox_ids: [inbox.id], required_qualification_fields: labels)
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  def run_turn(content, actions = [])
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                               sender: contact, content: content)
    provider = ->(**kwargs) { ScanSolo::TestMode::MockLlmProvider.call(**kwargs, fixture_actions: actions) }
    ScanSolo::AiTurn::TurnOrchestrator.call(message: message, llm_provider: provider)
    ScanSolo::AiTurn.find_by!(message_id: message.id)
  end

  def qualification_action(fields)
    { 'action_id' => 'qualification_field', 'params' => { 'fields' => fields } }
  end

  # The "Campos faltantes" list of the system message the provider received.
  def payload_missing_fields
    block = ScanSolo::TestMode::MockLlmProvider.last_payload[:system][/^Campos faltantes: (.*?)(?=\n\n## )/m, 1]
    block.lines(chomp: true).map { |line| line.delete_prefix('- ') }
  end

  it 'sends the fixed rules, keeps a native-only name missing (lead state RF-08) and a technical question in the history' do
    turn = run_turn('Boa tarde! Vocês conseguem escanear perto de um tubo de PVC enterrado?')

    expect(turn).to be_succeeded
    payload = ScanSolo::TestMode::MockLlmProvider.last_payload
    expect(payload[:system]).to include(*ScanSolo::AiTurn::PromptBuilder::CONTINUITY_RULES)
    expect(payload_missing_fields).to eq(labels)
    expect(payload[:messages]).to include(role: 'user', content: 'Boa tarde! Vocês conseguem escanear perto de um tubo de PVC enterrado?')
  end

  it 'lists only the remaining fields in the next payload after a partial answer' do
    run_turn('A obra é no Rio, com 800 m²', [qualification_action('cidade_uf' => 'Rio/RJ', 'area' => '800 m²')])

    run_turn('Qual o próximo passo?')

    expect(payload_missing_fields).to eq(labels - ['Cidade / UF', 'Área ou extensão'])
    expect(opportunity.reload).to be_em_qualificacao
  end

  it 'saves every datum given out of the config order in a single message' do
    run_turn('Quero escavar amanhã, obra no Rio, 800 m²',
             [qualification_action('prazo_desejado' => 'amanhã', 'cidade_uf' => 'Rio/RJ', 'area' => '800 m²')])

    expect(contact.reload.custom_attributes).to include('prazo_desejado' => 'amanhã', 'cidade_uf' => 'Rio/RJ', 'area' => '800 m²')

    run_turn('Certo')
    expect(payload_missing_fields).to eq(labels - ['Cidade / UF', 'Área ou extensão', 'Prazo desejado'])
  end

  it 'does not prompt again for any satisfied field when the conversation returns to the AI after a handoff' do
    agent = create(:user, account: account, role: :agent)
    run_turn('Sou da ACME, obra no Rio', [qualification_action('empresa' => 'ACME', 'Cidade / UF' => 'Rio/RJ')])
    ScanSolo::Handoff::HandoffService.call(conversation: conversation, reason: 'cliente pediu humano', actor: agent)
    ScanSolo::Handoff::ReturnToAiService.call(conversation: conversation, actor: agent)

    turn = run_turn('Voltei, pode continuar?')

    expect(turn).to be_succeeded
    expect(payload_missing_fields).to eq(labels - ['Cidade / UF', 'Empresa'])
    expect(turn.context_snapshot['pipeline_context']['missing_fields']).to eq(payload_missing_fields)
  end

  it 'reports an unknown fixture key in the turn action evidence and the ai_turns API' do
    agent = create(:user, account: account, role: :agent)

    turn = run_turn('Obra no Rio e minha cor favorita é azul',
                    [qualification_action('cidade_uf' => 'Rio/RJ', 'cor_favorita' => 'azul')])

    expect(contact.reload.custom_attributes).to eq('cidade_uf' => 'Rio/RJ')
    expect(turn.action_evidence.sole['result']['unrecognized_fields']).to eq(['cor_favorita'])

    get "/api/v1/accounts/#{account.id}/scan_solo/ai_turns/#{turn.correlation_id}", headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['action_evidence'].sole['result']['unrecognized_fields']).to eq(['cor_favorita'])
  end
end
