# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::AiTurn::PromptBuilder do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) do
    create(:contact, account: account, name: 'Contato Joana', custom_attributes: { 'budget' => 'orcamento-5000' })
  end
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:rule_values) do
    {
      role: 'papel-vendedor', objective: 'objetivo-vender', persona: 'persona-amigavel', tone: 'tom-cordial',
      instructions: 'instrucao-especial sk-live_abcdefghijklmnop', service_rules: 'regra-atendimento',
      service_hours: 'horario-9-18', response_limits: 'limite-curto', transfer_criteria: 'criterio-transferir',
      restricted_information: ['segredo-margem'], qualification_playbook: { 'passo' => 'playbook-perguntar-area' },
      required_qualification_fields: %w[budget area]
    }
  end
  let(:config) do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(rule_values.merge(name: 'Agente', enabled: true, allowed_inbox_ids: [inbox.id]))
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end
  let(:source) do
    ScanSolo::KnowledgeSource.create!(account: account, added_by: admin, source_type: :faq, origin: 'manual',
                                      title: 'Titulo-Fonte-Precos', content: 'conteudo-conhecimento sobre planos')
  end

  before do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_contato)
    ScanSolo::Knowledge::IngestionService.call(source: source, embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider)
    allow(ScanSolo::Knowledge::EmbeddingService).to receive(:call) do |content:, **|
      ScanSolo::TestMode::MockEmbeddingProvider.call(content: content)
    end
    allow(ScanSolo::AiTurn::ContextAssembler).to receive(:call).and_wrap_original do |original, **kwargs|
      original.call(**kwargs, memory_provider: ->(**) { [{ 'fato' => 'memoria-prefere-whatsapp' }] })
    end
  end

  def run_turn
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'historico-resposta')
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact,
                               content: 'historico-pergunta sobre planos')
    ScanSolo::AiTurn::TurnOrchestrator.call(message: message, llm_provider: ScanSolo::TestMode::MockLlmProvider)
    ScanSolo::AiTurn.find_by!(message_id: message.id)
  end

  describe 'RF-05: the provider payload carries every rule field and context block' do
    it 'contains each of the 12 rule values, with redaction applied to the whole payload' do
      config
      run_turn
      serialized = ScanSolo::TestMode::MockLlmProvider.last_payload.to_json

      %w[papel-vendedor objetivo-vender persona-amigavel tom-cordial instrucao-especial regra-atendimento horario-9-18
         limite-curto criterio-transferir segredo-margem playbook-perguntar-area].each do |value|
        expect(serialized).to include(value)
      end
      expect(ScanSolo::TestMode::MockLlmProvider.last_payload[:system]).to include("## Campos obrigatórios de qualificação\n- budget\n- area")
      expect(serialized).to include('[REDACTED]')
      expect(serialized).not_to include('sk-live_abcdefghijklmnop')
    end

    it 'contains the 5 context blocks: history as chat, knowledge with titles, contact, opportunity fields and memory' do
      config
      run_turn
      payload = ScanSolo::TestMode::MockLlmProvider.last_payload

      expect(payload[:messages]).to include({ role: 'assistant', content: 'historico-resposta' },
                                            { role: 'user', content: 'historico-pergunta sobre planos' })
      expect(payload[:system]).to include('### Titulo-Fonte-Precos', 'conteudo-conhecimento')
      expect(payload[:system]).to include('Nome: Contato Joana')
      expect(payload[:system]).to include('Etapa: Em Contato', 'Atributos: {"budget":"orcamento-5000"}', "Campos faltantes: - budget\n- area")
      expect(payload[:system]).to include('memoria-prefere-whatsapp')
    end

    it 'persists as knowledge_evidence exactly the chunks placed in the prompt (RF-46)' do
      config
      turn = run_turn

      expect(turn.knowledge_evidence).to match(
        source.knowledge_chunks.map do |chunk|
          hash_including('source_id' => source.id, 'source_title' => 'Titulo-Fonte-Precos', 'chunk_id' => chunk.id)
        end
      )
      expect(turn.knowledge_evidence.first['similarity_score']).to be_a(Numeric)
      expect(turn.latency_ms).to be_present
    end
  end

  describe '.call' do
    let(:context) do
      {
        conversation_history: [{ role: 'customer', content: nil, attachments: [], urls: [] }],
        contact_context: { available: false, reason: 'not_applicable' },
        pipeline_context: { available: false, reason: 'not_applicable' },
        lead_state_context: { available: false, reason: 'not_applicable' },
        proposal_context: { available: false, reason: 'not_applicable' },
        knowledge_context: { chunks: [], failure_reason: 'PG::Error: down' },
        durable_memory: { enabled: false }
      }
    end

    it 'offers only the given action ids in the output schema and hides turn-scoped ids from their params' do
      payload = described_class.call(config: config, context: context, offered_actions: %w[human_handoff cadence_signal])

      expect(payload[:schema][:schema][:properties][:actions][:items][:properties][:action_id][:enum]).to eq(%w[human_handoff cadence_signal])
      expect(payload[:system]).to include('- human_handoff:', '- cadence_signal:')
      expect(payload[:system]).not_to include('stage_transition', 'conversation_id', 'opportunity_id')
    end

    it 'renders a message with no text and no attachment as a text placeholder in the chat history' do
      payload = described_class.call(config: config, context: context, offered_actions: [])

      expect(payload[:messages]).to eq([{ role: 'user', content: '[mensagem sem texto]' }])
    end

    it 'RF-17: places the fixed continuity rules verbatim before the config-driven agent rules' do
      system = described_class.call(config: config, context: context, offered_actions: [])[:system]

      described_class::CONTINUITY_RULES.each do |rule|
        expect(system).to include(rule)
        expect(system.index(rule)).to be < system.index('## Regras do agente')
      end
      expect(system).to include(
        'Nunca pergunte novamente informação já presente no contato, nos campos coletados ou no histórico.',
        'Responda primeiro à pergunta/intenção atual do cliente; só depois pergunte no máximo 2 campos, ' \
        'apenas entre os campos elegíveis (faltantes).',
        'Cumprimente apenas na primeira resposta da conversa; não repita saudação depois.',
        'Liste em asked_fields as chaves dos campos que a resposta pergunta.'
      )
    end

    it 'RF-09, RF-13: allows up to 2 asked fields and answers a direct question first, before the agent rules' do
      system = described_class.call(config: config, context: context, offered_actions: [])[:system]
      direct_question_rule = 'Se a mensagem do cliente contiver uma pergunta direta, responda-a antes de qualquer pergunta de qualificação.'

      expect(described_class::CONTINUITY_RULES).to include(a_string_including('no máximo 2'))
      expect(described_class::CONTINUITY_RULES).not_to include(a_string_including('no máximo um campo'))
      expect(system).not_to include('no máximo um campo')
      expect(system.index(direct_question_rule)).to be < system.index('## Regras do agente')
    end

    it 'RF-16: describes location, PDF and links in the chat history instead of the empty-text placeholder' do
      context[:conversation_history] = [
        { role: 'customer', content: nil, urls: [],
          attachments: [{ id: 1, type: 'location', file_name: nil, lat: -22.9, long: -43.2, link: 'https://maps.google.com/?q=-22.9,-43.2',
                          extracted: true }] },
        { role: 'customer', content: '', urls: [],
          attachments: [{ id: 2, type: 'pdf', file_name: 'edital.pdf', lat: nil, long: nil, link: nil, extracted: true }] },
        { role: 'customer', content: 'segue o edital https://exemplo.com.br/edital', urls: ['https://exemplo.com.br/edital'], attachments: [] }
      ]

      messages = described_class.call(config: config, context: context, offered_actions: [])[:messages]

      expect(messages.pluck(:content)).to eq(
        [
          '[Anexo localização: lat -22.9, long -43.2, link https://maps.google.com/?q=-22.9,-43.2]',
          '[Anexo PDF: edital.pdf, extração: sim]',
          "segue o edital https://exemplo.com.br/edital\n[Links: https://exemplo.com.br/edital]"
        ]
      )
      expect(messages.pluck(:content)).not_to include('[mensagem sem texto]')
    end

    it 'CT-02, RF-10: requires reply, actions, asked_fields and summary in the output schema' do
      schema = described_class.call(config: config, context: context, offered_actions: [])[:schema][:schema]

      expect(schema[:required]).to eq(%w[reply actions asked_fields summary])
      expect(schema[:properties]).to include(asked_fields: { type: 'array', items: { type: 'string' } }, summary: { type: 'boolean' })
    end

    it 'RF-11a: adds the mandatory correction with the previous violation only on a regenerated attempt' do
      regenerated = described_class.call(config: config, context: context, offered_actions: [],
                                         previous_violation: 'confirmed_field_question')[:system]
      first = described_class.call(config: config, context: context, offered_actions: [])[:system]

      expect(regenerated).to include('## Correção obrigatória', 'confirmed_field_question')
      expect(first).not_to include('## Correção obrigatória')
    end

    it 'RF-17: keeps the fixed rules unchanged whatever the config fields say' do
      fixed_section = lambda do |agent_config|
        described_class.call(config: agent_config, context: context, offered_actions: [])[:system][/## Regras fixas de atendimento\n.*?\n\n/m]
      end
      edited = config.dup.tap do |agent_config|
        agent_config.assign_attributes(instructions: 'pergunte o nome sempre', service_rules: 'cumprimente sempre',
                                       required_qualification_fields: %w[Nome Telefone], tone: 'formal')
      end

      expect(fixed_section.call(edited)).to eq(fixed_section.call(config))
      expect(fixed_section.call(config)).to include(*described_class::CONTINUITY_RULES)
    end

    it 'RF-18: instructs registering every informed datum in one qualification_field call only when it is offered' do
      instruction = 'registrar todos os dados de qualificação informados na mensagem do cliente, numa única chamada com todos os campos'

      offered = described_class.call(config: config, context: context, offered_actions: %w[qualification_field])[:system]
      not_offered = described_class.call(config: config, context: context, offered_actions: %w[human_handoff])[:system]

      expect(offered).to include("- qualification_field: #{instruction}")
      expect(not_offered).not_to include(instruction)
    end
  end

  describe 'lead state section (RF-09, RF-15, RF-22, RF-24, RF-25)' do
    let(:rule_values) { super().merge(required_qualification_fields: ['Área']) }
    let(:opportunity) { ScanSolo::PipelineOpportunity.find_by!(conversation_id: conversation.id) }
    let(:writer) { ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state) }
    let(:message) do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact,
                       content: 'Qual a profundidade máxima do GPR?')
    end
    let(:render_system) do
      lambda do
        context = ScanSolo::AiTurn::ContextAssembler.call(
          message: message, config: config,
          attachment_reading: ScanSolo::AiTurn::AttachmentReader::Result.new(updates: [], evidence: [], urls: [])
        )
        described_class.call(config: config, context: context, offered_actions: [])[:system]
      end
    end

    before do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'resposta-ia',
                       additional_attributes: { 'scansolo_origin' => 'ai' })
    end

    it 'lists confirmed values, labeled inferred values and ordered eligible keys without confirmed or inferred ones' do
      writer.apply_field!(key: 'tempo_integracao', value: '30 minutos no mesmo dia', status: 'confirmado', source_message_id: message.id)
      writer.apply_field!(key: 'cidade_uf', value: 'RJ', status: 'inferido', source_message_id: message.id)

      system = render_system.call
      eligible = system[/Próximos campos elegíveis:\n(.*?)(?:\n\n|\z)/m, 1].lines.map(&:strip)

      expect(system).to include("## Estado do lead\nEtapa: Em Contato", 'Status da qualificação: em_andamento',
                                "Campos confirmados:\n- Tempo de integração: 30 minutos no mesmo dia",
                                '- Contato: Contato Joana (inferido)', '- Cidade / UF: RJ (inferido)',
                                "Campos obrigatórios não confirmados:\n- area (Área)")
      expect(eligible.first).to eq('- area (Área)')
      expect(eligible.index('- empresa (Empresa / razão social)')).to be < eligible.index('- cnpj (CNPJ)')
      expect(eligible.join).not_to include('tempo_integracao', 'cidade_uf', 'nome')
    end

    it 'has exactly one intent script line, which changes between orcamento and envio_documentos' do
      writer.set_intent!(intent: 'orcamento', source_message_id: message.id)
      budget_system = render_system.call
      writer.set_intent!(intent: 'envio_documentos', source_message_id: message.id)
      documents_system = render_system.call

      [budget_system, documents_system].each { |system| expect(system.scan(/^Roteiro da intenção:/).size).to eq(1) }
      expect(budget_system).to include("Roteiro da intenção: #{ScanSolo::AiTurn::LeadStatePrompt::INTENT_SCRIPTS.fetch('orcamento')}")
      expect(documents_system).to include("Roteiro da intenção: #{ScanSolo::AiTurn::LeadStatePrompt::INTENT_SCRIPTS.fetch('envio_documentos')}")
    end

    it 'offers no eligible field once the qualification is concluida' do
      writer.complete!(at: Time.current)

      expect(render_system.call).to include(
        "Próximos campos elegíveis: nenhum\nQualificação concluída: não faça perguntas de qualificação."
      )
    end

    it 'forbids the full summary with the fixed exception when nothing happened since the last AI reply' do
      system = render_system.call

      expect(system).to include("## Resumo dos dados\nresumo não permitido", ScanSolo::AiTurn::LeadStatePrompt::SUMMARY_EXCEPTION)
      expect(system).not_to include('resumo permitido')
    end

    it 'allows the full summary when a next action was recorded after the last AI reply' do
      travel(1.minute) { writer.record_next_action!(value: 'proposta', source_message_id: message.id) }

      expect(travel(2.minutes) { render_system.call }).to include("## Resumo dos dados\nresumo permitido")
    end

    it 'lists an authorized action next to the no-reconfirmation rule' do
      writer.authorize_action!(action: 'proposta', source_message_id: message.id)

      expect(render_system.call).to include(
        "Ações autorizadas (já pedidas ou autorizadas pelo cliente, não peça confirmação):\n- proposta",
        'Não peça nova confirmação para ação já pedida ou autorizada.'
      )
    end
  end
end
