# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Actions::Registry do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end

  describe '.register_all!' do
    it 'registers every action in the minimum commercial action set with exactly one classification' do
      described_class.register_all!

      %w[
        qualification_field stage_transition private_note proposal_generate
        proposal_approve proposal_send cadence_signal human_handoff
      ].each do |action_id|
        action = ScanSolo::AgentAction.find_by(action_id: action_id)

        expect(action).to be_present, "expected #{action_id} to be registered"
        expect(action.classification).to be_present
      end
    end
  end

  describe '.call' do
    it 'self-registers and executes the stage_transition action' do
      opportunity.update!(stage: :em_qualificacao)

      result = described_class.call(
        action_id: 'stage_transition',
        params: { opportunity_id: opportunity.id, target_stage: 'qualificado' },
        correlation_id: SecureRandom.uuid,
        idempotency_key: SecureRandom.uuid
      )

      expect(result.pending).to be false
      expect(opportunity.reload.stage).to eq('qualificado')
    end

    it 'executes the private_note action, creating a private message on the conversation' do
      result = described_class.call(
        action_id: 'private_note',
        params: { conversation_id: conversation.id, content: 'Cliente pediu desconto.' },
        correlation_id: SecureRandom.uuid,
        idempotency_key: SecureRandom.uuid
      )

      expect(result.pending).to be false
      expect(conversation.messages.where(private: true).last.content).to eq('Cliente pediu desconto.')
    end

    it 'executes the human_handoff action, moving the conversation to awaiting_human with the handoff note (RF-15)' do
      result = described_class.call(
        action_id: 'human_handoff',
        params: { conversation_id: conversation.id, reason: 'cliente pediu para falar com humano' },
        correlation_id: SecureRandom.uuid,
        idempotency_key: SecureRandom.uuid
      )

      expect(result.pending).to be false
      expect(ScanSolo::ConversationExtension.resolve_for(conversation)).to be_awaiting_human
      expect(conversation.messages.where(private: true).count).to eq(1)
    end

    it 'executes the cadence_signal action for a valid signal' do
      result = described_class.call(
        action_id: 'cadence_signal',
        params: { opportunity_id: opportunity.id, signal: 'full_reply' },
        correlation_id: SecureRandom.uuid,
        idempotency_key: SecureRandom.uuid
      )

      expect(result.pending).to be false
      expect(result.side_effect_result[:signal]).to eq('full_reply')
    end

    it 'rejects an invalid cadence_signal value via schema validation' do
      expect do
        described_class.call(
          action_id: 'cadence_signal',
          params: { opportunity_id: opportunity.id, signal: 'not_a_real_signal' },
          correlation_id: SecureRandom.uuid,
          idempotency_key: SecureRandom.uuid
        )
      end.to raise_error(ScanSolo::Actions::Executor::InvalidParamsError)
    end

    it 'executes proposal_generate as an automatic action' do
      allow(ScanSolo::Proposal::Integration).to receive(:provider!).and_return(ScanSolo::Proposal::MockProvider)
      result = described_class.call(
        action_id: 'proposal_generate',
        params: { opportunity_id: opportunity.id },
        correlation_id: SecureRandom.uuid,
        idempotency_key: SecureRandom.uuid
      )

      expect(result.pending).to be false
      expect(result.side_effect_result[:action]).to eq('proposal.generate')
      expect(ScanSolo::ProposalVersion.find(result.side_effect_result[:proposal_version_id])).to be_generated
    end

    it 'gates proposal_send behind confirmation (requires_confirmation classification)' do
      result = described_class.call(
        action_id: 'proposal_send',
        params: { opportunity_id: opportunity.id },
        correlation_id: SecureRandom.uuid,
        idempotency_key: SecureRandom.uuid
      )

      expect(result.pending).to be true
      expect(result.execution).to be_pending
    end

    it 'gates proposal_approve behind confirmation (requires_confirmation classification)' do
      result = described_class.call(
        action_id: 'proposal_approve',
        params: { opportunity_id: opportunity.id },
        correlation_id: SecureRandom.uuid,
        idempotency_key: SecureRandom.uuid
      )

      expect(result.pending).to be true
    end

    it 'executes the qualification_field action, updating allowed contact fields' do
      draft = ScanSolo::AiAgentConfig.draft_for!(account)
      draft.update!(name: 'Agente', enabled: true, required_qualification_fields: %w[budget])
      ScanSolo::AiAgent::PublishService.new(account: account).call
      opportunity.update!(stage: :em_qualificacao)

      result = described_class.call(
        action_id: 'qualification_field',
        params: { conversation_id: conversation.id, fields: { budget: '5000' } },
        correlation_id: SecureRandom.uuid,
        idempotency_key: SecureRandom.uuid
      )

      expect(result.pending).to be false
      expect(contact.reload.custom_attributes['budget']).to eq('5000')
    end
  end
end
