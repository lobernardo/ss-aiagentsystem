# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::PipelineOpportunity do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    described_class.create!(account: account, contact: contact, conversation: conversation, stage: :negociacao)
  end

  describe 'ESCALATION_REASONS' do
    it 'lists exactly the six escalation reasons' do
      expect(described_class::ESCALATION_REASONS).to eq(
        %w[duvida_sem_resposta sem_informacao_base negociacao duvida_proposta assunto_orcamento pedido_humano]
      )
    end
  end

  describe '#escalated_to_commercial?' do
    it 'is true with an escalation mark on a non-terminal stage' do
      opportunity.update!(escalated_to_commercial_at: Time.current, escalation_reason: 'negociacao')

      expect(opportunity.escalated_to_commercial?).to be true
    end

    it 'is false without an escalation mark' do
      expect(opportunity.escalated_to_commercial?).to be false
    end

    it 'is false in ganho or perdido even with an escalation mark' do
      opportunity.update!(escalated_to_commercial_at: Time.current, escalation_reason: 'pedido_humano')

      %w[ganho perdido].each do |stage|
        opportunity.stage = stage
        expect(opportunity.escalated_to_commercial?).to be(false), "expected false in #{stage}"
      end
    end
  end

  describe 'escalation_reason validation' do
    it 'accepts nil and each of the six reasons' do
      expect(opportunity).to be_valid

      described_class::ESCALATION_REASONS.each do |reason|
        opportunity.escalation_reason = reason
        expect(opportunity).to be_valid, "expected #{reason} to be valid"
      end
    end

    it 'rejects a reason outside the six values' do
      opportunity.escalation_reason = 'inventado'

      expect(opportunity).not_to be_valid
      expect(opportunity.errors[:escalation_reason]).to be_present
    end
  end
end
