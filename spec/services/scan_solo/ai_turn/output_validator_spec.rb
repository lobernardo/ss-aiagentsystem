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
end
