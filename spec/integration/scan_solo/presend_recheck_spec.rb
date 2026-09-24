# frozen_string_literal: true

require 'rails_helper'

# RF-10 / RF-02 / RF-04 / RF-19: every condition is flipped while the model is
# being invoked -- i.e. after the pre-invocation check passed and before the
# send -- so only the locked pre-send recheck can stop the reply.
RSpec.describe 'ScanSolo pre-send recheck' do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact)
  end
  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_contato)
  end
  let(:requested_actions) { [{ 'action_id' => 'stage_transition', 'params' => { 'target_stage' => 'em_qualificacao' } }] }

  before do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente ScanSolo', enabled: true, allowed_inbox_ids: [inbox.id])
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  def run_turn_flipping(&)
    actions = requested_actions
    provider = lambda do |**kwargs|
      instance_exec(&)
      ScanSolo::TestMode::MockLlmProvider.call(**kwargs, fixture_actions: actions)
    end

    ScanSolo::AiTurn::TurnOrchestrator.call(message: message, llm_provider: provider)
    ScanSolo::AiTurn.find_by!(message_id: message.id)
  end

  def republish(**attrs)
    ScanSolo::AiAgentConfig.draft_for!(account).update!(attrs)
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  {
    'not_eligible' => -> { republish(allowed_inbox_ids: []) },
    'human_controlled' => -> { ScanSolo::ConversationExtension.resolve_for(conversation).update!(ai_control_state: :human_active) },
    'config_unavailable' => -> { republish(enabled: false) },
    'human_replied' => lambda {
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: agent)
    },
    'superseded' => -> { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact) },
    'inbox_has_active_bot' => -> { create(:agent_bot_inbox, inbox: inbox, status: :active) }
  }.each do |reason, flip|
    it "suppresses with #{reason}, sending nothing and applying no action" do
      turn = run_turn_flipping(&flip)

      expect(turn).to have_attributes(invocation_status: 'suppressed', failure_reason: reason)
      expect(conversation.messages.outgoing.where(message_type: :outgoing, sender_type: 'AgentBot').count).to eq(0)
      expect(opportunity.reload).to be_em_contato
      expect(ScanSolo::AgentActionExecution.count).to eq(0)
    end
  end

  it 'suppresses an in-flight turn when the account kill switch is turned off (RF-04)' do
    turn = run_turn_flipping { account.update!(scansolo_enabled: false) }

    expect(turn).to have_attributes(invocation_status: 'suppressed', failure_reason: 'not_eligible')
    expect(conversation.messages.outgoing.count).to eq(0)
  end

  it 'sends nothing after a takeover during the model call and keeps enrollments paused (RF-19)' do
    definition = ScanSolo::CadenceDefinition.create!(stage: 'em_contato', version: 1, offsets: [24, 48])
    enrollment = ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: definition)

    turn = run_turn_flipping { ScanSolo::Handoff::TakeoverService.call(conversation: conversation, reason: 'humano', actor: agent) }

    expect(turn.failure_reason).to eq('human_controlled')
    expect(conversation.messages.outgoing.where(sender_type: 'AgentBot').count).to eq(0)
    expect(enrollment.reload).to be_paused
    expect(enrollment.attempts.pluck(:result).uniq).to eq(['scheduled'])
  end

  it 'leaves a turn failed by the stale sweeper untouched and unsent (RF-08)' do
    turn = run_turn_flipping do
      ScanSolo::AiTurn.find_by!(message_id: message.id).update!(invocation_status: :failed, failure_reason: 'stale_pending')
    end

    expect(turn).to have_attributes(invocation_status: 'failed', failure_reason: 'stale_pending')
    expect(conversation.messages.outgoing.count).to eq(0)
  end
end
