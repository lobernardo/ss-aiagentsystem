# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::AiTurn::InputGuardrail do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:config) do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(forbidden_subjects: ['concorrente XPTO'])
    draft
  end

  describe '.call' do
    it 'records a recorded guardrail outcome and an action list bounded below all registered actions' do
      outcome = described_class.call(config: config, content: 'Quero saber sobre planos.')

      expect(outcome).to include(:blocked, :allowed_actions)
      expect(outcome[:blocked]).to be false
      expect(outcome[:allowed_actions]).not_to be_empty
      expect(outcome[:allowed_actions]).not_to eq(described_class::ALL_ACTIONS)
    end

    it 'blocks when the inbound content hits a configured forbidden subject' do
      outcome = described_class.call(config: config, content: 'O que voces acham do concorrente XPTO?')

      expect(outcome[:blocked]).to be true
      expect(outcome[:forbidden_subject_hit]).to eq('concorrente XPTO')
    end

    it 'registers and offers lead_state_update on every turn (lead state CT-03)' do
      expect(described_class::ALL_ACTIONS).to include('lead_state_update')
      expect(ScanSolo::Actions::Registry::HANDLERS).to include('lead_state_update' => ScanSolo::Actions::LeadStateUpdateAction)
      expect(ScanSolo::AiTurn::PromptBuilder::ACTION_DESCRIPTIONS).to have_key('lead_state_update')
      expect(described_class.call(config: config, content: 'ola')[:allowed_actions]).to include('lead_state_update')
    end

    it 'never includes confirmation-only actions in the per-turn allowlist' do
      outcome = described_class.call(config: config, content: 'ola')

      expect(outcome[:allowed_actions]).not_to include('proposal_approve', 'proposal_send')
    end
  end
end
