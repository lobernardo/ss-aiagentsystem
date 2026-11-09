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

  # Escalação comercial RF-07/RF-08.
  describe 'commercial contact violations' do
    let(:published) { '+5511999999999' }
    let(:commercial_link) { 'https://wa.me/5511999999999?text=Ol%C3%A1%2C%20Artur%21%0ANome%3A%20Ana' }

    def violation(content, allowed: [published], link: commercial_link)
      described_class.call(content: content, commercial_link: link, allowed_phone_numbers: allowed)[:violation]
    end

    {
      'another wa.me link' => 'Fale com o comercial: https://wa.me/5511000000000',
      'an api.whatsapp.com link' => 'Chame em api.whatsapp.com/send?phone=5511000000000',
      'an unpublished Brazilian phone' => 'Ligue para (11) 98888-7777.',
      'an unpublished E.164 phone' => 'Ligue para +5511988887777.',
      'an unpublished phone without separators' => 'Ligue para 11988887777.'
    }.each do |kind, content|
      it "blocks #{kind} as unpublished_contact" do
        expect(violation(content)).to eq(:unpublished_contact)
      end
    end

    it 'blocks another wa.me link next to the commercial link' do
      expect(violation("#{commercial_link} ou https://wa.me/5511000000000")).to eq(:unpublished_contact)
    end

    {
      'the commercial link as the only link' => 'Fale direto com o Artur pelo WhatsApp: %<link>s',
      'the published number with separators' => 'O WhatsApp do Artur é (11) 99999-9999.',
      'the published number in E.164' => 'O WhatsApp do Artur é +55 11 99999-9999.',
      'a CNPJ' => 'CNPJ 12.345.678/0001-90 registrado.',
      'a CPF' => 'CPF 123.456.789-09 registrado.',
      'a CEP' => 'CEP 01310-100 registrado.',
      'a proposal number' => 'Sua proposta é a SS-2026-000123.',
      'a date' => 'A visita fica para 09/11/2026.',
      'a plain reply' => 'Posso te ajudar com mais alguma coisa?'
    }.each do |kind, content|
      it "does not block #{kind}" do
        expect(violation(format(content, link: commercial_link))).to be_nil
      end
    end

    it 'does not block a lead phone in the allowed list' do
      expect(violation('Vamos ligar no (21) 97777-6666.', allowed: [published, '+5521977776666'])).to be_nil
    end

    it 'keeps a value as a price claim, not an unpublished contact' do
      expect(violation('O total fica R$ 1.234,56.')).to eq(:price)
    end

    it 'blocks the internal contact name in any case' do
      expect(violation('Pode falar com o Luciano.')).to eq(:internal_name)
      expect(violation('fale com o LUCIANO')).to eq(:internal_name)
    end

    it 'checks the internal name before the unpublished contact' do
      expect(violation('fale com o Luciano em https://wa.me/5511000000000')).to eq(:internal_name)
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

    it 'lists the regenerable violations, including the 2 bulk and the 2 commercial contact ones (proposta-template-local RF-38 e)' do
      expect(described_class::REGENERABLE_VIOLATIONS).to contain_exactly(:confirmed_field_question, :question_limit, :field_not_missing,
                                                                         :qualification_closed, :bulk_out_of_scope, :bulk_incomplete,
                                                                         :internal_name, :unpublished_contact)
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
