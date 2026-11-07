# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::AiTurn::LeadStatePrompt do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account, name: 'Maria') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:message) { create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact, content: 'Oi') }
  let(:config) do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(required_qualification_fields: ['Área'])
    draft
  end
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
  end
  let(:writer) { ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state) }
  let(:retrieval_service) { Struct.new(:noop) { def self.call(**) = { results: [], failure_reason: nil } } }
  let(:render_block) do
    lambda do
      context = ScanSolo::AiTurn::ContextAssembler.call(
        message: message, config: config, retrieval_service: retrieval_service,
        attachment_reading: ScanSolo::AiTurn::AttachmentReader::Result.new(updates: [], evidence: [], urls: [])
      )
      described_class.call(lead_state_context: context[:lead_state_context])['Estado do lead']
    end
  end

  before { writer.set_intent!(intent: 'orcamento', source_message_id: message.id) }

  describe 'up-front list offer (proposta-template-local RF-34, RF-36)' do
    it 'is given once with a budget intent, em_andamento and no recorded offer' do
      block = render_block.call

      expect(block.scan(described_class::COLLECTION_OFFER).size).to eq(1)
      expect(described_class::COLLECTION_OFFER).to include('Posso te mandar a lista do que preciso?', 'não pergunte nenhum campo')
    end

    it 'is also given for a convite_cotacao intent' do
      writer.set_intent!(intent: 'convite_cotacao', source_message_id: message.id)

      expect(render_block.call).to include(described_class::COLLECTION_OFFER)
    end

    it 'is given to an old state with null collection columns' do
      expect(opportunity.lead_state.reload).to have_attributes(collection_offered_at: nil, collection_mode: nil)
      expect(render_block.call).to include(described_class::COLLECTION_OFFER)
    end

    it 'is not given for a duvida intent' do
      writer.set_intent!(intent: 'duvida', source_message_id: message.id)

      expect(render_block.call).not_to include(described_class::COLLECTION_OFFER)
    end

    it 'is not given once the qualification is concluida' do
      writer.complete!(at: Time.current)

      expect(render_block.call).not_to include(described_class::COLLECTION_OFFER)
    end

    it 'never comes back once the offer was recorded' do
      writer.record_collection_offer!(at: Time.current, source_message_id: message.id)

      expect(render_block.call).not_to include(described_class::COLLECTION_OFFER)
    end
  end

  describe 'answer to the list offer' do
    before { writer.record_collection_offer!(at: Time.current, source_message_id: message.id) }

    it 'lists the relevant pending fields to ask in one message on acceptance, with the progressive alternative' do
      block = render_block.call

      expect(block).to include(described_class::COLLECTION_ANSWER, "- area (Área)\n", described_class::COLLECTION_ANSWER_PROGRESSIVE)
      expect(block).not_to include(described_class::COLLECTION_BULK)
    end

    it 'is no longer given once the lead chose a mode' do
      writer.set_collection_mode!(mode: 'progressiva', source_message_id: message.id)

      expect(render_block.call).not_to include(described_class::COLLECTION_ANSWER)
    end
  end

  describe 'bulk collection (proposta-template-local RF-38 d)' do
    before { writer.record_collection_offer!(at: Time.current, source_message_id: message.id) }

    it 'asks every eligible field in one message with the "não sei / não tenho / não se aplica" notice in em_bloco' do
      writer.set_collection_mode!(mode: 'em_bloco', source_message_id: message.id)

      block = render_block.call
      expect(block).to include(described_class::COLLECTION_BULK)
      expect(described_class::COLLECTION_BULK).to include('"não sei", "não tenho" ou "não se aplica"', 'numa única mensagem')
    end

    it 'has no bulk instruction in progressiva' do
      writer.set_collection_mode!(mode: 'progressiva', source_message_id: message.id)

      expect(render_block.call).not_to include(described_class::COLLECTION_BULK)
    end

    it 'has no bulk instruction once the qualification is concluida' do
      writer.set_collection_mode!(mode: 'em_bloco', source_message_id: message.id)
      writer.complete!(at: Time.current)

      expect(render_block.call).not_to include(described_class::COLLECTION_BULK)
    end
  end
end
