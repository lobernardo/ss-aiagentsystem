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
  let(:send_round) do
    lambda do
      trigger = create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact, created_at: 1.hour.ago)
      reply = create(:message, account: account, conversation: conversation, message_type: :outgoing, created_at: 1.hour.ago)
      ScanSolo::AiTurn.create!(message: trigger, conversation: conversation, correlation_id: SecureRandom.uuid, invocation_status: :succeeded,
                               response_message_id: reply.id, context_snapshot: { 'asked_fields' => ['area'] })
    end
  end
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

  describe 'initial explanation (proposta-template-local RF-34)' do
    it 'is in the block with a budget intent, em_andamento and 0 rounds' do
      expect(render_block.call).to include(described_class::COLLECTION_INTRO)
      expect(described_class::COLLECTION_INTRO).to include(
        'Para preparar seu orçamento corretamente, preciso coletar algumas informações rápidas sobre o serviço.'
      )
    end

    it 'is also given for a convite_cotacao intent' do
      writer.set_intent!(intent: 'convite_cotacao', source_message_id: message.id)

      expect(render_block.call).to include(described_class::COLLECTION_INTRO)
    end

    it 'disappears after 1 round' do
      send_round.call

      expect(render_block.call).not_to include(described_class::COLLECTION_INTRO)
    end

    it 'is not given for a duvida intent' do
      writer.set_intent!(intent: 'duvida', source_message_id: message.id)

      expect(render_block.call).not_to include(described_class::COLLECTION_INTRO)
    end

    it 'is not given once the qualification is concluida' do
      writer.complete!(at: Time.current)

      expect(render_block.call).not_to include(described_class::COLLECTION_INTRO)
    end
  end

  describe 'one-time bulk offer (proposta-template-local RF-36)' do
    it 'is not given with 1 round' do
      send_round.call

      expect(render_block.call).not_to include(described_class::COLLECTION_OFFER)
    end

    it 'is given once with 2 rounds and no recorded offer' do
      2.times { send_round.call }

      block = render_block.call
      expect(block.scan(described_class::COLLECTION_OFFER).size).to eq(1)
      expect(described_class::COLLECTION_OFFER).to include(
        'Se preferir, posso te mandar de uma vez todas as informações que ainda preciso e você responde tudo junto. Quer assim?',
        'lead_state_update.collection_mode'
      )
    end

    it 'is given to an old state with null collection columns' do
      2.times { send_round.call }

      expect(opportunity.lead_state.reload).to have_attributes(collection_offered_at: nil, collection_mode: nil)
      expect(render_block.call).to include(described_class::COLLECTION_OFFER)
    end

    it 'never comes back once the offer was recorded' do
      2.times { send_round.call }
      writer.record_collection_offer!(at: Time.current, source_message_id: message.id)
      send_round.call

      expect(render_block.call).not_to include(described_class::COLLECTION_OFFER)
    end
  end

  describe 'bulk collection (proposta-template-local RF-38 d)' do
    before do
      2.times { send_round.call }
      writer.record_collection_offer!(at: Time.current, source_message_id: message.id)
    end

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
