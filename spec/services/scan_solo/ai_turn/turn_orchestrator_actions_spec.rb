# frozen_string_literal: true

require 'rails_helper'

# RF-12..RF-17: model-requested actions run only through
# ScanSolo::Actions::Registry, after the pre-send recheck and in the same
# transaction as the reply.
RSpec.describe ScanSolo::AiTurn::TurnOrchestrator do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:other_conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_contato)
  end
  let(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact,
                     content: 'Meu orçamento é 5000')
  end

  let(:one_of_each) do
    [
      { 'action_id' => 'qualification_field', 'params' => { 'fields' => { 'budget' => '5000' } } },
      { 'action_id' => 'stage_transition', 'params' => { 'target_stage' => 'qualificado' } },
      { 'action_id' => 'private_note', 'params' => { 'content' => 'Cliente com orçamento definido' } },
      { 'action_id' => 'cadence_signal', 'params' => { 'signal' => 'partial_reply' } },
      { 'action_id' => 'proposal_generate', 'params' => {} },
      { 'action_id' => 'human_handoff', 'params' => { 'reason' => 'pronto para negociar' } }
    ]
  end

  before do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente ScanSolo', enabled: true, allowed_inbox_ids: [inbox.id], required_qualification_fields: %w[budget])
    ScanSolo::AiAgent::PublishService.new(account: account).call
    allow(ScanSolo::Proposal::Integration).to receive_messages(configured?: true, provider!: ScanSolo::Proposal::MockProvider)
  end

  def run_turn(actions, target: message)
    provider = ->(**kwargs) { ScanSolo::TestMode::MockLlmProvider.call(**kwargs, fixture_actions: actions) }
    described_class.call(message: target, llm_provider: provider)
    ScanSolo::AiTurn.find_by!(message_id: target.id)
  end

  def ai_replies
    conversation.messages.outgoing.where(private: false)
  end

  describe 'RF-12: one execution per offered action id, keyed by the turn' do
    it 'creates one AgentActionExecution per action with the turn correlation id and position-based idempotency keys' do
      turn = run_turn(one_of_each)

      expect(turn).to be_succeeded
      executions = ScanSolo::AgentActionExecution.order(:id)
      expect(executions.map(&:action_id)).to eq(one_of_each.pluck('action_id'))
      expect(executions.map(&:correlation_id).uniq).to eq([turn.correlation_id])
      expect(executions.map(&:idempotency_key)).to eq(one_of_each.each_with_index.map { |a, i| "#{turn.correlation_id}:#{i}:#{a['action_id']}" })
      expect(executions.map(&:turn_id).uniq).to eq([turn.id])
      expect(turn.action_evidence.pluck('action_id')).to eq(one_of_each.pluck('action_id'))
      expect(ai_replies.count).to eq(1)
    end

    it 'creates no new execution when the same message is processed again' do
      run_turn(one_of_each)

      expect { run_turn(one_of_each) }.not_to change(ScanSolo::AgentActionExecution, :count)
    end

    it 'offers the six base ids plus proposal_generate only while the proposal integration is configured' do
      run_turn([])
      offered = ScanSolo::TestMode::MockLlmProvider.last_payload[:schema][:schema][:properties][:actions][:items][:properties][:action_id][:enum]
      expect(offered).to eq(%w[qualification_field stage_transition private_note proposal_generate cadence_signal human_handoff lead_state_update])

      allow(ScanSolo::Proposal::Integration).to receive(:configured?).and_return(false)
      next_message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact)
      run_turn([], target: next_message)
      offered = ScanSolo::TestMode::MockLlmProvider.last_payload[:schema][:schema][:properties][:actions][:items][:properties][:action_id][:enum]
      expect(offered).to eq(%w[qualification_field stage_transition private_note cadence_signal human_handoff lead_state_update])
    end

    it 'always acts on the turn conversation, ignoring ids chosen by the model' do
      run_turn([{ 'action_id' => 'private_note', 'params' => { 'conversation_id' => other_conversation.id, 'content' => 'nota' } }])

      expect(conversation.messages.where(private: true).count).to eq(1)
      expect(other_conversation.messages.where(private: true).count).to eq(0)
    end

    it 'issues the proposal provider request once the turn commits' do
      contact.update!(custom_attributes: { 'budget' => '5000' })

      run_turn([{ 'action_id' => 'proposal_generate', 'params' => {} }])

      expect(ScanSolo::ProposalVersion.sole).to be_generated
    end

    it 'never issues the proposal provider request when the turn rolls back' do
      allow(ScanSolo::Proposal::MockProvider).to receive(:request_generation)
      allow(ScanSolo::AiTurn::ResponseSender).to receive(:call).and_raise(ActiveRecord::RecordInvalid)
      contact.update!(custom_attributes: { 'budget' => '5000' })

      run_turn([{ 'action_id' => 'proposal_generate', 'params' => {} }])

      expect(ScanSolo::Proposal::MockProvider).not_to have_received(:request_generation)
      expect(ScanSolo::ProposalVersion.count).to eq(0)
    end
  end

  describe 'RF-13: all-or-nothing on an action the executor rejects' do
    {
      'an unregistered id' => { 'action_id' => 'delete_everything', 'params' => {} },
      'a registered id that is never offered' => { 'action_id' => 'proposal_approve', 'params' => {} },
      'schema-invalid params' => { 'action_id' => 'cadence_signal', 'params' => { 'signal' => 'bogus' } }
    }.each do |kind, bad_action|
      it "fails the turn with 0 messages and 0 side effects for #{kind}" do
        turn = run_turn([{ 'action_id' => 'private_note', 'params' => { 'content' => 'antes' } }, bad_action])

        expect(turn).to be_failed
        expect(turn.failure_reason).to start_with('ScanSolo::Actions::Executor::')
        expect(conversation.messages.outgoing.count).to eq(0)
        expect(ScanSolo::AgentActionExecution.count).to eq(0)
      end
    end
  end

  describe 'RF-14: AI stage moves' do
    it 'records a forbidden target as a rejection in action_evidence and keeps the stage' do
      turn = run_turn([{ 'action_id' => 'stage_transition', 'params' => { 'target_stage' => 'ganho' } }])

      expect(opportunity.reload).to be_em_contato
      expect(turn.action_evidence.sole['result']).to include('status' => 'rejected', 'target_stage' => 'ganho')
      expect(ai_replies.count).to eq(1)
    end
  end

  describe 'RF-15: AI handoff' do
    it 'sends the turn reply, leaves 1 note, awaiting_human, paused enrollments and 0 replies to the next message' do
      definition = ScanSolo::CadenceDefinition.create!(stage: 'em_contato', version: 1, offsets: [24, 48])
      enrollment = travel_to(1.hour.ago) { ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: definition) }

      turn = run_turn([{ 'action_id' => 'human_handoff', 'params' => { 'reason' => 'cliente pediu humano' } }])

      expect(turn).to be_succeeded
      expect(ai_replies.count).to eq(1)
      expect(conversation.messages.where(private: true).count).to eq(1)
      expect(ScanSolo::ConversationExtension.resolve_for(conversation)).to be_awaiting_human
      expect(enrollment.reload).to be_paused

      next_message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact)
      expect(run_turn([], target: next_message)).to have_attributes(invocation_status: 'suppressed', failure_reason: 'human_controlled')
      expect(ai_replies.count).to eq(1)
    end
  end

  describe 'RF-16 (a) / RF-17: cadence effects of actions' do
    let(:definition) { ScanSolo::CadenceDefinition.create!(stage: 'em_qualificacao', version: 1, offsets: [24, 48, 72]) }

    before { opportunity.update!(stage: :em_qualificacao) }

    it 'cancels every remaining attempt when the action records the last required field' do
      enrollment = travel_to(1.hour.ago) { ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: definition) }

      run_turn([{ 'action_id' => 'qualification_field', 'params' => { 'fields' => { 'budget' => '5000' } } }])

      expect(enrollment.attempts.scheduled.count).to eq(0)
    end

    it 'opts the contact out through cadence_signal opt_out' do
      enrollment = travel_to(1.hour.ago) { ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: definition) }

      run_turn([{ 'action_id' => 'cadence_signal', 'params' => { 'signal' => 'opt_out' } }])

      expect(ScanSolo::ContactExtension.opted_out?(contact)).to be true
      expect(enrollment.reload).to be_cancelled
    end
  end
end
