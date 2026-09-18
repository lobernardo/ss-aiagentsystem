# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::AiTurn::ContextAssembler do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account, name: 'Maria', email: 'maria@example.com') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  let(:message) do
    create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact,
                     content: 'Qual o preco do plano?')
  end

  describe '.call' do
    it 'references all five RF-39 sources, each either populated or explicitly not_applicable' do
      snapshot = described_class.call(message: message, retrieval_service: mock_retrieval_service)

      expect(snapshot.keys).to include(:conversation_history, :contact_context, :pipeline_context,
                                       :proposal_context, :knowledge_context)

      expect(snapshot[:conversation_history]).to be_an(Array)
      expect(snapshot[:contact_context]).to include(available: true, name: 'Maria')
      expect(snapshot[:pipeline_context]).to eq(available: false, reason: 'not_applicable')
      expect(snapshot[:proposal_context]).to eq(available: false, reason: 'not_applicable')
      expect(snapshot[:knowledge_context]).to eq(results: [], failure_reason: nil)
    end

    it 'includes recent canonical conversation history from native Message records' do
      snapshot = described_class.call(message: message, retrieval_service: mock_retrieval_service)

      expect(snapshot[:conversation_history].last).to include(role: 'customer', content: 'Qual o preco do plano?')
    end

    it 'includes pipeline context when an opportunity exists for the conversation' do
      ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation,
                                            stage: :em_qualificacao)

      snapshot = described_class.call(message: message, retrieval_service: mock_retrieval_service)

      expect(snapshot[:pipeline_context]).to include(available: true, stage: 'em_qualificacao')
    end

    describe 'RF-40: durable memory is auxiliary and subordinate to canonical history' do
      it 'defaults to disabled without removing conversation_history' do
        snapshot = described_class.call(message: message, retrieval_service: mock_retrieval_service)

        expect(snapshot[:durable_memory]).to eq(enabled: false)
        expect(snapshot[:conversation_history]).not_to be_empty
      end

      it 'is included as an auxiliary layer when a memory_provider is configured' do
        snapshot = described_class.call(
          message: message,
          retrieval_service: mock_retrieval_service,
          memory_provider: ->(**) { [{ fact: 'cliente prefere WhatsApp' }] }
        )

        expect(snapshot[:durable_memory][:enabled]).to be true
        expect(snapshot[:durable_memory][:entries]).not_to be_empty
        expect(snapshot[:conversation_history]).not_to be_empty
      end
    end
  end

  def mock_retrieval_service
    Struct.new(:noop) { def self.call(**) = { results: [], failure_reason: nil } }
  end
end
