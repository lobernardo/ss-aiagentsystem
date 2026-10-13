# frozen_string_literal: true

require 'rails_helper'

# proposta-template-local T13 (RF-26, RF-29, RF-30, RF-34..RF-39, RNF-09):
# end-to-end qualification with `nao_informado` and the collection UX. Every
# turn runs the real ScanSolo::AiTurn::TurnOrchestrator with
# ScanSolo::TestMode::MockLlmProvider (no real LLM, WebMock on) against the
# agent config published by the spec itself (own instructions,
# `model_selection`, `allowed_inbox_ids` and `opt_out_keywords`), which no
# turn may create or change.
RSpec.describe 'ScanSolo qualification with nao_informado' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Ana', email: nil, phone_number: nil, custom_attributes: {}) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_contato)
  end
  let(:required_fields) { ['Empresa', 'Profundidade de investigação'] }
  let(:enabled) { true }
  let(:instructions) { 'Instruções publicadas: atenda leads de georadar com cordialidade e objetividade.' }
  let(:confirmed_fields) { { 'empresa' => 'ACME' } }
  let(:payloads) { [] }
  let(:received_configs) { [] }
  # Read lazily, after the publish below and before the first turn.
  let(:config_rows) { ScanSolo::AiAgentConfig.order(:id).pluck(:id, :updated_at) }

  before do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente ScanSolo', enabled: enabled, allowed_inbox_ids: [inbox.id], required_qualification_fields: required_fields,
                  instructions: instructions, model_selection: 'gpt-4.1', opt_out_keywords: %w[PARAR SAIR])
    ScanSolo::AiAgent::PublishService.new(account: account).call

    seed = create_message('Olá, preciso de um orçamento de georadar')
    writer = ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state)
    writer.set_intent!(intent: 'orcamento', source_message_id: seed.id)
    confirmed_fields.each { |key, value| writer.apply_field!(key: key, value: value, status: 'confirmado', source_message_id: seed.id) }
  end

  def create_message(content, target = conversation)
    create(:message, account: account, inbox: target.inbox, conversation: target, message_type: :incoming, sender: contact, content: content)
  end

  # One MockLlmProvider response per model call of this turn, in order. No
  # turn creates or changes a config row (compatibility with the published agent).
  def run_turn(content, *responses)
    rows = config_rows
    message = create_message(content)
    calls = 0
    provider = lambda do |**kwargs|
      calls += 1
      payloads << kwargs[:payload]
      received_configs << kwargs[:config]
      ScanSolo::TestMode::MockLlmProvider.call(**kwargs, **responses.fetch([calls, responses.size].min - 1, {}))
    end
    ScanSolo::AiTurn::TurnOrchestrator.call(message: message, llm_provider: provider)
    expect(ScanSolo::AiAgentConfig.order(:id).pluck(:id, :updated_at)).to eq(rows)
    ScanSolo::AiTurn.find_by!(message_id: message.id)
  end

  def notify_listener(message)
    ScanSolo::ConversationListener.instance.message_created(Events::Base.new('message_created', Time.zone.now, { message: message }))
  end

  def fields_action(fields)
    { 'action_id' => 'qualification_field', 'params' => { 'fields' => fields } }
  end

  def mode_action(mode)
    { 'action_id' => 'lead_state_update', 'params' => { 'collection_mode' => mode } }
  end

  def section(payload, title)
    payload[:system][/^## #{title}\n(.*?)(?=\n\n## )/m, 1]
  end

  def lead_state
    opportunity.lead_state.reload
  end

  def sent_turns
    ScanSolo::AiTurn.where(conversation: conversation).where.not(response_message_id: nil).order(:id)
  end

  def offered_events
    ScanSolo::LeadStateEvent.where(lead_state_id: lead_state.id, subject: 'collection_mode', key: 'collection_offered_at')
  end

  describe 'the 4-turn "não sei" conversation (RF-30, RF-29, RF-34)' do
    let(:depth_question) { 'Qual a profundidade de investigação que você precisa?' }

    it 'concludes once on "não sei", never asks again and keeps concluida when the value arrives', :aggregate_failures do
      turn1 = run_turn('Preciso de um orçamento para a obra da ACME', { fixture_response: depth_question, fixture_asked_fields: ['profundidade'] })
      expect(turn1).to be_succeeded
      expect(turn1.context_snapshot['asked_fields']).to eq(['profundidade'])

      turn2 = run_turn('não sei', { fixture_actions: [fields_action('profundidade' => { 'value' => 'não sei', 'status' => 'nao_informado' })] })
      expect(turn2).to be_succeeded
      expect(lead_state.fields['profundidade']).to include('value' => 'não sei', 'status' => 'nao_informado')
      expect(lead_state).to be_concluida
      expect(ScanSolo::AuditEvent.where(event_type: 'lead_state.qualification_completed').count).to eq(1)
      expect(ScanSolo::QuoteRequestJob).to have_been_enqueued.with(opportunity.id).once

      turn3 = run_turn('Ok, obrigado',
                       { fixture_response: 'Pode confirmar a profundidade de investigação?', fixture_asked_fields: ['profundidade'] },
                       { fixture_response: 'Combinado, a equipe já está preparando o seu orçamento.' })
      expect(turn3).to be_succeeded
      expect(turn3.context_snapshot['output_regeneration']).to eq('first_attempt_violation' => 'qualification_closed')
      expect(turn3.context_snapshot['asked_fields']).to eq([])
      expect(conversation.messages.outgoing.where(content: 'Pode confirmar a profundidade de investigação?')).to be_empty

      turn4 = run_turn('Na verdade são 3 metros', { fixture_actions: [fields_action('profundidade' => '3 metros')] })
      expect(turn4).to be_succeeded
      expect(lead_state.fields['profundidade']).to include('value' => '3 metros', 'status' => 'confirmado')
      expect(lead_state).to be_concluida
      expect(ScanSolo::QuoteRequestJob).to have_been_enqueued.with(opportunity.id).once
      expect(ScanSolo::AuditEvent.where(event_type: 'lead_state.qualification_completed').count).to eq(1)

      # RF-34: the initial explanation reaches only the 1st turn that asks fields.
      expect(payloads.size).to eq(5)
      expect(payloads.count { |payload| payload[:system].include?(ScanSolo::AiTurn::LeadStatePrompt::COLLECTION_INTRO) }).to eq(1)
      expect(payloads.first[:system]).to include(ScanSolo::AiTurn::LeadStatePrompt::COLLECTION_INTRO)
      expect(conversation.messages.outgoing.where(content: depth_question).count).to eq(1)
    end

    it 'keeps the published instructions unchanged, only appends the new rules and uses the published model', :aggregate_failures do
      run_turn('Preciso de um orçamento para a obra da ACME', { fixture_response: depth_question, fixture_asked_fields: ['profundidade'] })

      published = ScanSolo::AiAgentConfig.published_for(account)
      payload = payloads.sole
      expect(section(payload, 'Regras do agente')).to include("Instruções: #{instructions}")
      expect(section(payload, 'Regras fixas de atendimento')).to end_with("- #{ScanSolo::AiTurn::PromptBuilder::CONTINUITY_RULES.last}")
      expect(ScanSolo::AiTurn::PromptBuilder::CONTINUITY_RULES.last).to include('registre o campo com status nao_informado')
      expect(section(payload, 'Estado do lead')).to end_with(ScanSolo::AiTurn::LeadStatePrompt::COLLECTION_INTRO)
      expect(received_configs.map(&:id)).to eq([published.id])
      expect(ScanSolo::AiAgent::ModelResolver.resolve(config: received_configs.sole)).to include(provider: 'openai', model: 'gpt-4.1')
      expect(published).to have_attributes(allowed_inbox_ids: [inbox.id], opt_out_keywords: %w[PARAR SAIR], enabled: true)
    end
  end

  context 'with an empty required list (LS/RF-04 preserved)' do
    let(:required_fields) { [] }

    it 'records nao_informado, never asks it again and stays em_andamento with 0 quote requests', :aggregate_failures do
      run_turn('Preciso de um orçamento', { fixture_asked_fields: ['profundidade'] })
      run_turn('não sei', { fixture_actions: [fields_action('profundidade' => { 'value' => 'não sei', 'status' => 'nao_informado' })] })
      turn3 = run_turn('E agora?', { fixture_asked_fields: ['profundidade'] }, { fixture_asked_fields: ['area'] })

      expect(turn3.context_snapshot['output_regeneration']).to eq('first_attempt_violation' => 'field_not_missing')
      expect(lead_state.fields['profundidade']).to include('value' => 'não sei', 'status' => 'nao_informado')
      expect(lead_state).to be_em_andamento
      expect(ScanSolo::QuoteRequestJob).not_to have_been_enqueued
      asked = sent_turns.flat_map { |turn| turn.context_snapshot['asked_fields'] }
      expect(asked).to eq(%w[profundidade area])
    end
  end

  describe 'the one-time bulk offer (RF-35, RF-36)' do
    it 'instructs the offer in exactly 1 sent turn of 8 and records 1 collection_offered_at, the model taking no action', :aggregate_failures do
      run_turn('Preciso de um orçamento', { fixture_asked_fields: ['profundidade'] })
      run_turn('Ainda estou vendo', { fixture_asked_fields: ['area'] })
      6.times { |index| run_turn("Mensagem #{index + 3}") }

      expect(sent_turns.count).to eq(8)
      expect(sent_turns.count { |turn| turn.context_snapshot['collection_offer_instructed'] }).to eq(1)
      expect(sent_turns.third.context_snapshot['collection_offer_instructed']).to be(true)
      expect(payloads.count { |payload| payload[:system].include?(ScanSolo::AiTurn::LeadStatePrompt::COLLECTION_OFFER) }).to eq(1)
      expect(offered_events.count).to eq(1)
      expect(lead_state.collection_offered_at).to be_present
      expect(lead_state.collection_mode).to be_nil
    end

    it 'brings the instruction back on the next turn when the instructed reply fails to send', :aggregate_failures do
      run_turn('Preciso de um orçamento', { fixture_asked_fields: ['profundidade'] })
      run_turn('Ainda estou vendo', { fixture_asked_fields: ['area'] })

      allow(ScanSolo::AiTurn::ResponseSender).to receive(:call).and_raise(StandardError, 'falha simulada no envio')
      failed = run_turn('Oi?')
      expect(failed).to be_failed
      expect(failed.context_snapshot['collection_offer_instructed']).to be(true)
      expect(lead_state.collection_offered_at).to be_nil
      expect(offered_events).to be_empty

      allow(ScanSolo::AiTurn::ResponseSender).to receive(:call).and_call_original
      retried = run_turn('Oi, tudo bem?')
      expect(retried).to be_succeeded
      expect(retried.context_snapshot['collection_offer_instructed']).to be(true)
      expect(payloads.last[:system]).to include(ScanSolo::AiTurn::LeadStatePrompt::COLLECTION_OFFER)
      expect(lead_state.collection_offered_at).to be_present
      expect(offered_events.count).to eq(1)
    end
  end

  describe 'the bulk choice (RF-37, RF-38)' do
    let(:required_fields) { ['Empresa', 'Profundidade de investigação', 'Integração'] }
    let(:confirmed_fields) do
      { 'empresa' => 'ACME', 'tipo_servico' => 'GeoRadar', 'restricoes_acesso' => 'Portaria', 'prazo_desejado' => '30 dias',
        'condicoes_especiais' => 'Nenhuma' }
    end
    let(:relevant) { %w[area metragem profundidade integracao_seguranca] }

    before do
      run_turn('Preciso de um orçamento', { fixture_asked_fields: ['profundidade'] })
      run_turn('Ainda estou vendo', { fixture_asked_fields: ['area'] })
      run_turn('Ok', { fixture_response: 'Se preferir, posso te mandar tudo de uma vez. Quer assim?' })
    end

    it 'asks exactly the relevant pending set after the acceptance and never asks profundidade after "não sei"', :aggregate_failures do
      accepted = run_turn('Sim, pode mandar tudo',
                          { fixture_actions: [mode_action('em_bloco')], fixture_asked_fields: [*relevant, 'cnpj'] },
                          { fixture_actions: [mode_action('em_bloco')], fixture_asked_fields: relevant })
      expect(accepted).to be_succeeded
      expect(accepted.context_snapshot['output_regeneration']).to eq('first_attempt_violation' => 'bulk_out_of_scope')
      expect(accepted.context_snapshot['asked_fields']).to match_array(relevant)
      expect(lead_state.collection_mode).to eq('em_bloco')

      answer = [fields_action('area' => '800 m²', 'profundidade' => { 'value' => 'não sei', 'status' => 'nao_informado' })]
      answered = run_turn('área 800 m², profundidade não sei',
                          { fixture_actions: answer, fixture_asked_fields: %w[profundidade integracao_seguranca] },
                          { fixture_actions: answer, fixture_asked_fields: ['integracao_seguranca'] })
      expect(section(payloads.last, 'Estado do lead')).to include(ScanSolo::AiTurn::LeadStatePrompt::COLLECTION_BULK)
      expect(answered).to be_succeeded
      expect(answered.context_snapshot['asked_fields']).to eq(['integracao_seguranca'])
      expect(lead_state.fields['area']).to include('value' => '800 m²', 'status' => 'confirmado')
      expect(lead_state.fields['profundidade']).to include('value' => 'não sei', 'status' => 'nao_informado')
      expect(lead_state).to be_em_andamento
      expect(sent_turns.where('id >= ?', answered.id).flat_map { |turn| turn.context_snapshot['asked_fields'] }).not_to include('profundidade')
    end

    it 'never sends a reply asking more than 2 fields after the refusal' do
      run_turn('Prefiro ir respondendo aos poucos', { fixture_actions: [mode_action('progressiva')], fixture_asked_fields: ['area'] })
      2.times do
        turn = run_turn('Certo', { fixture_asked_fields: %w[area metragem integracao_seguranca] }, { fixture_asked_fields: %w[area metragem] })
        expect(turn.context_snapshot['output_regeneration']).to eq('first_attempt_violation' => 'question_limit')
      end

      expect(lead_state.collection_mode).to eq('progressiva')
      expect(sent_turns.map { |turn| turn.context_snapshot['asked_fields'].size }).to all(be <= 2)
    end
  end

  describe 'an old lead state and the sole writer (RF-39)' do
    it 'offers the bulk collection to a state whose collection columns are NULL' do
      expect(ScanSolo::LeadState.where(id: lead_state.id).pick(:collection_offered_at, :collection_mode)).to eq([nil, nil])

      run_turn('Preciso de um orçamento', { fixture_asked_fields: ['profundidade'] })
      run_turn('Ainda estou vendo', { fixture_asked_fields: ['area'] })
      offered = run_turn('Ok')

      expect(offered.context_snapshot['collection_offer_instructed']).to be(true)
      expect(section(payloads.last, 'Estado do lead')).to include(ScanSolo::AiTurn::LeadStatePrompt::COLLECTION_OFFER)
      expect(lead_state.collection_offered_at).to be_present
      expect(lead_state.collection_mode).to be_nil
    end

    it 'finds only the Writer writing the collection columns' do
      writes = Rails.root.glob('app/**/*.rb').select do |path|
        path.readlines.any? do |line|
          line.match?(/collection_offered_at|collection_mode/) && line.match?(/update(_column|_columns|!)?\(|\.collection_(offered_at|mode) =/)
        end
      end

      expect(writes.map { |path| path.relative_path_from(Rails.root).to_s }).to eq(['app/services/scan_solo/lead_state/writer.rb'])
    end
  end

  describe 'eligibility of the published agent' do
    it 'starts no turn for an inbox outside allowed_inbox_ids' do
      other_conversation = create(:conversation, account: account, inbox: create(:inbox, account: account), contact: contact)
      message = create_message('Preciso de um orçamento', other_conversation)

      rows = config_rows
      notify_listener(message)

      expect(ScanSolo::Eligibility.for_message(message).reason).to eq('inbox_not_allowlisted')
      expect(ScanSolo::AiTurnJob).not_to have_been_enqueued.with(message.id)
      expect(ScanSolo::AiTurn.where(message_id: message.id)).to be_empty
      expect(ScanSolo::AiAgentConfig.order(:id).pluck(:id, :updated_at)).to eq(rows)
    end

    context 'with the published agent disabled' do
      let(:enabled) { false }

      it 'starts no turn' do
        message = create_message('Preciso de um orçamento')

        rows = config_rows
        notify_listener(message)

        expect(ScanSolo::Eligibility.for_message(message).reason).to eq('config_unavailable')
        expect(ScanSolo::AiTurnJob).not_to have_been_enqueued.with(message.id)
        expect(ScanSolo::AiTurn.where(message_id: message.id)).to be_empty
        expect(ScanSolo::AiAgentConfig.order(:id).pluck(:id, :updated_at)).to eq(rows)
      end
    end
  end
end
