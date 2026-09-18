# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::AiAgentConfig do
  let(:account) { create(:account) }

  it 'persists and round-trips every RF-20 field' do
    draft = described_class.draft_for!(account)

    draft.update!(
      name: 'Agente Comercial',
      enabled: true,
      model_provider: 'openai',
      model_selection: 'gpt-4.1',
      role: 'SDR virtual',
      objective: 'Qualificar leads',
      persona: 'Consultivo e objetivo',
      tone: 'Profissional',
      instructions: 'Responda sempre em pt-BR',
      service_rules: 'Nunca prometa desconto',
      qualification_playbook: %w[orcamento prazo],
      required_qualification_fields: %w[orcamento],
      restricted_information: %w[preco_interno],
      forbidden_subjects: %w[concorrentes],
      transfer_criteria: 'Cliente pede humano',
      response_limits: 'Ate 3 mensagens por turno',
      service_hours: '09:00-20:00 America/Sao_Paulo'
    )

    reloaded = described_class.find(draft.id)
    described_class::FIELDS.each do |field|
      expect(reloaded.public_send(field)).to eq(draft.public_send(field))
    end
  end

  it 'only allows one draft row per account' do
    described_class.draft_for!(account)

    expect do
      described_class.create!(account: account, status: :draft)
    end.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'allows multiple published rows per account (version history)' do
    described_class.create!(account: account, status: :published)

    expect do
      described_class.create!(account: account, status: :published)
    end.not_to raise_error
  end

  describe '.draft_for!' do
    it 'creates the draft once and returns the same row on subsequent calls' do
      first = described_class.draft_for!(account)
      second = described_class.draft_for!(account)

      expect(second.id).to eq(first.id)
    end
  end

  describe '.published_for' do
    it 'returns nil before any publish has occurred' do
      expect(described_class.published_for(account)).to be_nil
    end
  end
end
