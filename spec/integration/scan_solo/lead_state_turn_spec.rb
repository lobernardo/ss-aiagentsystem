# frozen_string_literal: true

require 'rake'
require 'rails_helper'

# Lead state RF-01a, RF-05, RF-06, RF-11a, RF-13, RF-18a, RF-19, RF-21, RF-22,
# RF-24, RNF-08(8)(9): end-to-end lead state through real turns. Every turn
# runs the real ScanSolo::AiTurn::TurnOrchestrator with
# ScanSolo::TestMode::MockLlmProvider; assertions are made on what reached the
# provider (`MockLlmProvider.last_payload` or the captured payloads) and on
# the persisted lead state -- never on the mock's reply text.
RSpec.describe 'ScanSolo lead state turn' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Ana', email: nil, phone_number: nil, custom_attributes: {}) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:stage) { :em_contato }
  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: stage)
  end
  let(:required_fields) { ['Área', 'Tempo de integração'] }
  let(:payloads) { [] }

  before do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente ScanSolo', enabled: true, allowed_inbox_ids: [inbox.id], required_qualification_fields: required_fields)
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  def create_message(content)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact, content: content)
  end

  # One MockLlmProvider response per model call, in order; every payload
  # the provider receives is kept in `payloads`.
  def run_turn(message, *responses)
    provider = lambda do |**kwargs|
      payloads << kwargs[:payload]
      ScanSolo::TestMode::MockLlmProvider.call(**kwargs, **responses.fetch([payloads.size, responses.size].min - 1, {}))
    end
    ScanSolo::AiTurn::TurnOrchestrator.call(message: message, llm_provider: provider)
    ScanSolo::AiTurn.find_by!(message_id: message.id)
  end

  def fields_action(fields)
    { fixture_actions: [{ 'action_id' => 'qualification_field', 'params' => { 'fields' => fields } }] }
  end

  def lead_state_section(payload = ScanSolo::TestMode::MockLlmProvider.last_payload)
    payload[:system][/^## Estado do lead\n(.*?)(?=\n\n## )/m, 1]
  end

  def lead_state
    opportunity.lead_state.reload
  end

  def ai_replies
    conversation.messages.outgoing.where(private: false)
  end

  it '(a) shows only the corrected tempo_integracao as the current value in the next payload (RF-06)' do
    run_turn(create_message('A integração de segurança leva uma diária'), fields_action('tempo_integracao' => 'uma diária'))
    run_turn(create_message('Corrigindo: são 30 minutos no mesmo dia'), fields_action('tempo_integracao' => '30 minutos no mesmo dia'))

    run_turn(create_message('Certo, e agora?'))

    expect(lead_state_section).to include('Tempo de integração: 30 minutos no mesmo dia')
    expect(lead_state_section).not_to include('uma diária')
    expect(lead_state.fields['tempo_integracao']).to include('value' => '30 minutos no mesmo dia', 'status' => 'confirmado')
    expect(lead_state.events.where(subject: 'field', key: 'tempo_integracao').order(:id).last)
      .to have_attributes(previous_value: 'uma diária', new_value: '30 minutos no mesmo dia')
  end

  it '(b) keeps the technical question in the history and the answer-first rule in the system (RF-13)' do
    question = 'Vocês conseguem escanear perto de um tubo de PVC enterrado?'

    expect(run_turn(create_message(question))).to be_succeeded

    payload = ScanSolo::TestMode::MockLlmProvider.last_payload
    expect(payload[:messages]).to include(role: 'user', content: question)
    expect(payload[:system]).to include('Se a mensagem do cliente contiver uma pergunta direta, ' \
                                        'responda-a antes de qualquer pergunta de qualificação.')
  end

  it '(c) rejects both attempts with qualification_closed once the qualification is concluded (RF-22)' do
    run_turn(create_message('800 m² e 30 minutos de integração'), fields_action('area' => '800 m²', 'tempo_integracao' => '30 minutos'))
    expect(lead_state).to be_concluida
    payloads.clear

    turn = run_turn(create_message('Mais alguma coisa?'), { fixture_asked_fields: ['bairro'] })

    expect(payloads.size).to eq(2)
    expect(payloads.map { |payload| lead_state_section(payload) }).to all(include('Próximos campos elegíveis: nenhum'))
    expect(turn.context_snapshot['output_regeneration']).to eq('first_attempt_violation' => 'qualification_closed')
    expect(turn).to have_attributes(invocation_status: 'failed', failure_reason: 'output validation blocked: qualification_closed')
    expect(ai_replies.count).to eq(1)
  end

  it '(d) regenerates once with the violation and sends 1 message (RF-11a)' do
    run_turn(create_message('São 800 m²'), fields_action('area' => '800 m²'))
    payloads.clear

    turn = run_turn(create_message('Qual o próximo passo?'), { fixture_asked_fields: ['area'] }, { fixture_asked_fields: ['tempo_integracao'] })

    expect(payloads.size).to eq(2)
    expect(payloads.first[:system]).not_to include('## Correção obrigatória')
    expect(payloads.last[:system]).to include('## Correção obrigatória', 'confirmed_field_question')
    expect(turn).to be_succeeded
    expect(ai_replies.count).to eq(2)
    expect(ai_replies.where('messages.id > ?', turn.message_id).count).to eq(1)
  end

  it '(e) persists 0 PDF fields and 0 messages after 2 rejections (RF-05, RF-19)' do
    message = create_message('Segue o convite')
    attachment = message.attachments.new(account_id: account.id, file_type: :file)
    attachment.file.attach(io: Rails.root.join('spec/fixtures/files/scansolo/lead_state_company.pdf').open,
                           filename: 'lead_state_company.pdf', content_type: 'application/pdf')
    attachment.save!

    turn = run_turn(message, { fixture_asked_fields: %w[bairro cargo prazo_proposta] })

    expect(payloads.size).to eq(2)
    expect(payloads.first[:messages]).to include(role: 'user', content: "Segue o convite\n[Anexo PDF: lead_state_company.pdf, extração: sim]")
    expect(lead_state_section(payloads.first)).to include('CNPJ: 12.345.678/0001-90 (inferido)')
    expect(turn).to have_attributes(invocation_status: 'failed', failure_reason: 'output validation blocked: question_limit')
    expect(lead_state.fields.slice('cnpj', 'empresa', 'endereco_obra').values.pluck('status')).to all(eq('faltante'))
    expect(ScanSolo::LeadStateEvent.where(key: %w[cnpj empresa endereco_obra])).to be_empty
    expect(ai_replies.count).to eq(0)
  end

  it '(f) writes a map URL as inferido link_local from the message with 0 HTTP requests (RF-18a)' do
    url = 'https://maps.app.goo.gl/AbC123xyz'
    message = create_message("O local da obra é este: #{url}")

    expect(run_turn(message)).to be_succeeded

    expect(lead_state.fields['link_local']).to include('value' => url, 'status' => 'inferido', 'source_message_id' => message.id,
                                                       'source_attachment_id' => nil)
    expect(a_request(:any, /.*/)).not_to have_been_made
  end

  it '(g) concludes from em_contato with 2 stage events and 1 completion audit event (RF-21)' do
    turn = run_turn(create_message('800 m² e 30 minutos de integração'), fields_action('area' => '800 m²', 'tempo_integracao' => '30 minutos'))

    expect(turn).to be_succeeded
    expect(opportunity.reload).to be_qualificado
    expect(ScanSolo::PipelineStageEvent.where(opportunity_id: opportunity.id).order(:id).pluck(:from_stage, :to_stage))
      .to eq([%w[em_contato em_qualificacao], %w[em_qualificacao qualificado]])
    expect(ScanSolo::AuditEvent.where(event_type: 'lead_state.qualification_completed').sole.correlation_id).to eq(turn.correlation_id)
  end

  it '(h) lists proposta as authorized in the next prompt after "pode mandar a proposta" (RF-24)' do
    message = create_message('Pode mandar a proposta')
    run_turn(message, { fixture_actions: [{ 'action_id' => 'lead_state_update', 'params' => { 'authorized_action' => 'proposta' } }] })

    run_turn(create_message('Obrigado'))

    expect(lead_state_section).to include("Ações autorizadas (já pedidas ou autorizadas pelo cliente, não peça confirmação):\n- proposta")
    expect(lead_state.authorized_actions.sole).to include('action' => 'proposta', 'source_message_id' => message.id)
  end

  describe '(i) an opportunity in negociacao with the backfilled lead state (RF-01a)' do
    let(:stage) { :negociacao }

    # The opportunity existed before the lead state table.
    before do
      ScanSolo::LeadStateEvent.delete_all
      ScanSolo::LeadState.delete_all
      Rake::Task['scansolo:backfill_lead_states'].reenable
    end

    it 'is not requalified: both attempts asking nome are rejected with qualification_closed and 0 messages' do
      expect { Rake::Task['scansolo:backfill_lead_states'].invoke }.to output("Lead states created: 1\n").to_stdout
      expect(lead_state).to be_concluida
      expect(lead_state.fields['nome']).to include('value' => 'Ana', 'status' => 'inferido')

      turn = run_turn(create_message('Oi, alguma novidade?'), { fixture_asked_fields: ['nome'] })

      expect(payloads.size).to eq(2)
      expect(payloads.map { |payload| lead_state_section(payload) }).to all(include('Próximos campos elegíveis: nenhum'))
      expect(turn).to have_attributes(invocation_status: 'failed', failure_reason: 'output validation blocked: qualification_closed')
      expect(ai_replies.count).to eq(0)
    end
  end
end
