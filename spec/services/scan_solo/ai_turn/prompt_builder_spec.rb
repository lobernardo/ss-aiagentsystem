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
      expect(payload[:system]).to include('Etapa: Em Contato', 'budget: orcamento-5000', 'Campos faltantes: - area')
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
        conversation_history: [{ role: 'customer', content: nil }],
        contact_context: { available: false, reason: 'not_applicable' },
        pipeline_context: { available: false, reason: 'not_applicable' },
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

    it 'renders an attachment-only message as a text placeholder in the chat history' do
      payload = described_class.call(config: config, context: context, offered_actions: [])

      expect(payload[:messages]).to eq([{ role: 'user', content: '[mensagem sem texto]' }])
    end
  end
end
