# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Commercial::EscalationGate do
  describe 'QUALIFIED_STAGES' do
    it 'lists the three qualified stages' do
      expect(described_class::QUALIFIED_STAGES).to eq(%w[qualificado proposta_enviada negociacao])
    end
  end

  describe '.decide' do
    let(:stages) { ScanSolo::PipelineOpportunity.stages.keys }
    let(:combinations) do
      stages.product([true, false], [0, 1], [true, false], [true, false]).map do |stage, quote_sent, count, request, escalated|
        { stage: stage, quote_sent: quote_sent, email_redirect_count: count, commercial_request: request, previously_escalated: escalated }
      end
    end

    def expected_decision(input)
      return :none unless input[:commercial_request]
      return :etapa_nao_qualificada unless %w[qualificado proposta_enviada negociacao].include?(input[:stage])
      return :orcamento_nao_enviado unless input[:quote_sent]
      return :primeiro_pedido_email if input[:email_redirect_count].zero?

      :approved
    end

    it 'covers all 128 combinations of the RF-11 matrix with the expected decision' do
      expect(stages.size).to eq(8)
      expect(combinations.size).to eq(128)

      combinations.each do |input|
        expect(described_class.decide(**input)).to eq(expected_decision(input)), "unexpected decision for #{input}"
      end
    end

    it 'approves only a qualified stage with the quote sent, count >= 1 and a commercial request' do
      approved = combinations.select { |input| described_class.decide(**input) == :approved }

      expect(approved.size).to eq(6)
      expect(approved).to all(include(quote_sent: true, email_redirect_count: 1, commercial_request: true))
      expect(approved.map { |input| input[:stage] }.uniq).to match_array(%w[qualificado proposta_enviada negociacao])
    end

    it 'returns :none without a commercial request in every stage' do
      combinations.reject { |input| input[:commercial_request] }.each do |input|
        expect(described_class.decide(**input)).to eq(:none)
      end
    end

    it 'refuses with :etapa_nao_qualificada before qualificado and in ganho/perdido, whatever the other inputs' do
      other_inputs = [true, false].product([0, 1], [true, false])

      %w[novo_lead em_contato em_qualificacao ganho perdido].each do |stage|
        other_inputs.each do |quote_sent, count, escalated|
          decision = described_class.decide(stage: stage, quote_sent: quote_sent, email_redirect_count: count,
                                            commercial_request: true, previously_escalated: escalated)
          expect(decision).to eq(:etapa_nao_qualificada), "expected refusal in #{stage}"
        end
      end
    end

    it 'refuses with :orcamento_nao_enviado in a qualified stage without the quote sent (RF-03)' do
      described_class::QUALIFIED_STAGES.product([0, 1], [true, false]).each do |stage, count, escalated|
        decision = described_class.decide(stage: stage, quote_sent: false, email_redirect_count: count,
                                          commercial_request: true, previously_escalated: escalated)
        expect(decision).to eq(:orcamento_nao_enviado)
      end
    end

    it 'refuses with :primeiro_pedido_email on the first request with the quote sent (RF-04)' do
      described_class::QUALIFIED_STAGES.product([true, false]).each do |stage, escalated|
        decision = described_class.decide(stage: stage, quote_sent: true, email_redirect_count: 0,
                                          commercial_request: true, previously_escalated: escalated)
        expect(decision).to eq(:primeiro_pedido_email)
      end
    end

    it 'approves a new explicit request after the link (RF-08)' do
      decision = described_class.decide(stage: 'negociacao', quote_sent: true, email_redirect_count: 3,
                                        commercial_request: true, previously_escalated: true)

      expect(decision).to eq(:approved)
    end

    it 'accepts the stage as a symbol' do
      decision = described_class.decide(stage: :qualificado, quote_sent: true, email_redirect_count: 1,
                                        commercial_request: true, previously_escalated: false)

      expect(decision).to eq(:approved)
    end

    it 'gives the same decision when each combination is evaluated twice (RNF-03)' do
      first_run = combinations.map { |input| described_class.decide(**input) }
      second_run = combinations.map { |input| described_class.decide(**input) }

      expect(second_run).to eq(first_run)
    end
  end

  describe '.quote_sent?' do
    let(:account) { create(:account) }
    let(:contact) { create(:contact, account: account) }
    let(:conversation) { create(:conversation, account: account, contact: contact) }
    let(:opportunity) do
      ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
    end

    it 'is false without a quote request' do
      expect(described_class.quote_sent?(opportunity)).to be false
    end

    it 'is false with a quote request whose sent_at is nil' do
      ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid)

      expect(described_class.quote_sent?(opportunity.reload)).to be false
    end

    it 'is true with a quote request whose sent_at is set' do
      ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid, sent_at: Time.current)

      expect(described_class.quote_sent?(opportunity.reload)).to be true
    end
  end
end
