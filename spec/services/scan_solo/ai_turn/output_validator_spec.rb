# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::AiTurn::OutputValidator do
  describe '.call' do
    it 'blocks a model attempt to state a price without an approved proposal.generate/proposal.send result' do
      result = described_class.call(content: 'O plano custa R$ 199,90 por mes.')

      expect(result[:blocked]).to be true
      expect(result[:violation]).to eq(:price)
    end

    it 'allows a price claim once the caller marks it as validated by a deterministic action result' do
      result = described_class.call(content: 'O plano custa R$ 199,90 por mes.', validated_claims: { price: true })

      expect(result[:blocked]).to be false
    end

    it 'blocks an unvalidated proposal-sent confirmation claim' do
      result = described_class.call(content: 'A proposta foi enviada para o seu WhatsApp.')

      expect(result[:blocked]).to be true
      expect(result[:violation]).to eq(:proposal_sent)
    end

    it 'blocks an unvalidated delivery-status claim' do
      result = described_class.call(content: 'Seu pedido entregue com sucesso.')

      expect(result[:blocked]).to be true
      expect(result[:violation]).to eq(:delivery_status)
    end

    it 'does not block ordinary content with no transactional claim' do
      result = described_class.call(content: 'Posso te ajudar com mais alguma coisa?')

      expect(result[:blocked]).to be false
      expect(result[:violation]).to be_nil
    end
  end

  describe 'RF-06: restricted_information' do
    it 'blocks output containing a configured restricted entry, case-insensitively' do
      result = described_class.call(content: 'Nossa MARGEM INTERNA é de 40%.', restricted_information: ['margem interna'])

      expect(result).to eq(blocked: true, violation: :restricted_information)
    end

    it 'ignores blank restricted entries' do
      expect(described_class.call(content: 'Olá!', restricted_information: ['', nil])[:blocked]).to be false
    end
  end

  describe 'lead state violations (RF-11, RF-12, RF-17, RF-22)' do
    let(:account) { create(:account) }
    let(:contact) { create(:contact, account: account) }
    let(:conversation) { create(:conversation, account: account, contact: contact) }
    let(:opportunity) do
      ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
    end
    let(:writer) { ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state) }
    let(:config) do
      draft = ScanSolo::AiAgentConfig.draft_for!(account)
      draft.update!(required_qualification_fields: ['Área', 'Data desejada'])
      draft
    end
    let(:pending_updates) { [] }
    let(:lead_state) { ScanSolo::LeadState::Projection.call(opportunity: opportunity.reload, config: config, pending_updates: pending_updates) }

    def validate(content, asked_fields)
      described_class.call(content: content, asked_fields: asked_fields, lead_state: lead_state)
    end

    it 'rejects a question naming a confirmed field by a 2-token label even with empty asked_fields' do
      writer.apply_field!(key: 'data_desejada', value: '10/10', status: 'confirmado', source_message_id: nil)

      expect(validate('Perfeito! Qual a data desejada?', [])).to eq(blocked: true, violation: :confirmed_field_question)
    end

    it 'does not detect a confirmed field lexically through a 1-token spelling' do
      writer.apply_field!(key: 'area', value: '800 m²', status: 'confirmado', source_message_id: nil)

      expect(validate('Qual a área aproximada?', [])).to eq(blocked: false, violation: nil)
    end

    it 'rejects a confirmed key listed in asked_fields' do
      writer.apply_field!(key: 'area', value: '800 m²', status: 'confirmado', source_message_id: nil)

      expect(validate('Qual a área aproximada?', ['area'])).to eq(blocked: true, violation: :confirmed_field_question)
    end

    it 'accepts a statement that mentions a confirmed value without asking' do
      writer.apply_field!(key: 'area', value: '800 m²', status: 'confirmado', source_message_id: nil)

      expect(validate('Para 800 m² indicamos o GPR.', [])).to eq(blocked: false, violation: nil)
    end

    it 'rejects more than 2 asked fields' do
      expect(validate('Qual o cargo, o CNPJ e o bairro?', %w[cargo cnpj bairro])).to eq(blocked: true, violation: :question_limit)
    end

    it 'accepts 2 missing asked fields' do
      expect(validate('Qual o cargo e o CNPJ?', %w[cargo cnpj])).to eq(blocked: false, violation: nil)
    end

    it 'rejects an inferred asked field' do
      writer.apply_field!(key: 'cnpj', value: '12.345.678/0001-90', status: 'inferido', source_message_id: nil)

      expect(validate('Pode confirmar o CNPJ?', ['cnpj'])).to eq(blocked: true, violation: :field_not_missing)
    end

    it 'rejects an asked key outside the catalog' do
      expect(validate('Qual a sua cor favorita?', ['cor_favorita'])).to eq(blocked: true, violation: :field_not_missing)
    end

    context 'with a location in the current message' do
      let(:pending_updates) { [{ key: 'link_local', value: 'https://www.google.com/maps?q=-22.9,-43.2', source_attachment_id: 1 }] }

      it 'rejects asking the link it filled' do
        expect(validate('Pode mandar o link do local?', ['link_local'])).to eq(blocked: true, violation: :field_not_missing)
      end
    end

    context 'when the qualification is concluida' do
      before { writer.complete!(at: Time.current) }

      it 'rejects any asked field' do
        expect(validate('Qual o bairro?', ['bairro'])).to eq(blocked: true, violation: :qualification_closed)
      end

      it 'accepts a reply that asks nothing' do
        expect(validate('Obrigado! Vamos preparar a proposta.', [])).to eq(blocked: false, violation: nil)
      end
    end

    it 'accepts a full summary and a confirmation request for an authorized action' do
      writer.apply_field!(key: 'area', value: '800 m²', status: 'confirmado', source_message_id: nil)
      writer.apply_field!(key: 'data_desejada', value: '10/10', status: 'confirmado', source_message_id: nil)
      writer.authorize_action!(action: 'proposta', source_message_id: nil)

      expect(validate('Resumo: área de 800 m² e data desejada 10/10. Posso seguir com a proposta?', [])).to eq(blocked: false, violation: nil)
    end

    it 'keeps the existing violations first' do
      writer.apply_field!(key: 'data_desejada', value: '10/10', status: 'confirmado', source_message_id: nil)

      expect(validate('O plano custa R$ 199,90. Qual a data desejada?', ['data_desejada'])).to eq(blocked: true, violation: :price)
    end

    it 'lists the regenerable violations, including the 2 bulk ones (proposta-template-local RF-38 e)' do
      expect(described_class::REGENERABLE_VIOLATIONS).to contain_exactly(:confirmed_field_question, :question_limit, :field_not_missing,
                                                                         :qualification_closed, :bulk_out_of_scope, :bulk_incomplete)
    end

    it 'rejects asking a nao_informado field while another required one is faltante (proposta-template-local RF-29)' do
      writer.apply_field!(key: 'profundidade', value: 'não sei', status: 'nao_informado', source_message_id: nil)

      expect(lead_state.status[:missing_fields]).to include('area')
      expect(validate('Qual a profundidade?', ['profundidade'])).to eq(blocked: true, violation: :field_not_missing)
    end

    describe 'bulk collection (proposta-template-local RF-38)' do
      let(:config) do
        draft = ScanSolo::AiAgentConfig.draft_for!(account)
        draft.update!(required_qualification_fields: ['Área'])
        draft
      end
      let(:relevant) { %w[area metragem profundidade integracao_seguranca] }
      let(:message) { create(:message, account: account, conversation: conversation, message_type: :incoming) }

      def validate_bulk(asked_fields, bulk_started:)
        described_class.call(content: 'Pode me passar estes dados?', asked_fields: asked_fields, lead_state: lead_state, bulk_started: bulk_started)
      end

      before do
        { 'tipo_servico' => 'GeoRadar', 'restricoes_acesso' => 'Portaria', 'prazo_desejado' => '30 dias', 'condicoes_especiais' => 'Nenhuma' }
          .each { |key, value| writer.apply_field!(key: key, value: value, status: 'confirmado', source_message_id: message.id) }
      end

      context 'with em_bloco' do
        before do
          writer.record_collection_offer!(at: Time.current, source_message_id: message.id)
          writer.set_collection_mode!(mode: 'em_bloco', source_message_id: message.id)
        end

        it 'accepts the 4 relevant pending fields on the acceptance turn, without question_limit' do
          expect(lead_state.relevant_pending_keys).to eq(relevant)
          expect(validate_bulk(relevant, bulk_started: true)).to eq(blocked: false, violation: nil)
        end

        it 'rejects 3 of them on the acceptance turn with bulk_incomplete' do
          expect(validate_bulk(relevant.first(3), bulk_started: true)).to eq(blocked: true, violation: :bulk_incomplete)
        end

        it 'rejects the 4 plus cnpj with bulk_out_of_scope' do
          expect(validate_bulk(relevant + ['cnpj'], bulk_started: true)).to eq(blocked: true, violation: :bulk_out_of_scope)
        end

        it 'accepts a single relevant field on a following turn' do
          expect(validate_bulk(['profundidade'], bulk_started: false)).to eq(blocked: false, violation: nil)
        end

        it 'keeps rejecting a confirmed field asked by its label' do
          expect(described_class.call(content: 'Qual o tipo de serviço?', asked_fields: [], lead_state: lead_state, bulk_started: false))
            .to eq(blocked: true, violation: :confirmed_field_question)
        end

        it 'keeps qualification_closed once the qualification is concluida' do
          writer.complete!(at: Time.current)

          expect(validate_bulk(['profundidade'], bulk_started: false)).to eq(blocked: true, violation: :qualification_closed)
        end
      end

      it 'rejects 3 fields with question_limit in progressiva' do
        writer.record_collection_offer!(at: Time.current, source_message_id: message.id)
        writer.set_collection_mode!(mode: 'progressiva', source_message_id: message.id)

        expect(validate_bulk(relevant.first(3), bulk_started: false)).to eq(blocked: true, violation: :question_limit)
      end

      it 'rejects 3 fields with question_limit without a collection mode' do
        expect(validate_bulk(relevant.first(3), bulk_started: true)).to eq(blocked: true, violation: :question_limit)
      end
    end
  end
end
