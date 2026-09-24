# frozen_string_literal: true

require 'rails_helper'

# RF-18 / CT-09: drives the real native message_created -> AsyncDispatcher ->
# EventDispatcherJob -> ScanSolo::ConversationListener path, so only a manual,
# non-private human reply takes over; everything ScanSolo sends and every
# assignment change leaves the AI in control.
RSpec.describe 'ScanSolo implicit takeover' do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:contact) { create(:contact, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente ScanSolo', enabled: true, allowed_inbox_ids: [inbox.id])
    ScanSolo::AiAgent::PublishService.new(account: account).call
    conversation
  end

  def through_dispatcher(&)
    perform_enqueued_jobs(only: EventDispatcherJob, &)
  end

  def extension
    ScanSolo::ConversationExtension.resolve_for(conversation)
  end

  def takeover_events
    ScanSolo::AuditEvent.where(event_type: 'handoff.takeover')
  end

  it 'takes over on a manual agent reply' do
    through_dispatcher { Messages::MessageBuilder.new(agent, conversation, { content: 'Olá, sou a Ana' }).perform }

    expect(extension).to be_human_active
    expect(takeover_events.sole.payload['trigger']).to eq('human_reply')
  end

  it 'ignores a private note' do
    through_dispatcher { Messages::MessageBuilder.new(agent, conversation, { content: 'nota', private: true }).perform }

    expect(extension).to be_ai_active
    expect(takeover_events).to be_none
  end

  it 'ignores a manual conversation assignment' do
    through_dispatcher { conversation.update!(assignee: agent) }

    expect(extension).to be_ai_active
    expect(takeover_events).to be_none
  end

  it 'ignores the native auto-assignment' do
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ agent.id.to_s => 'online' })

    through_dispatcher do
      AutoAssignment::AgentAssignmentService.new(conversation: conversation, allowed_agent_ids: [agent.id.to_s]).perform
    end

    expect(conversation.reload.assignee).to eq(agent)
    expect(extension).to be_ai_active
    expect(takeover_events).to be_none
  end

  it 'ignores a cadence message' do
    through_dispatcher do
      ScanSolo::Messaging::NativeTemplateSender.call(conversation: conversation, template_reference: 'scansolo_cadence_novo_lead_v1_step1',
                                                     origin: 'cadence')
    end

    expect(extension).to be_ai_active
    expect(takeover_events).to be_none
  end

  it 'ignores a proposal send even though it carries the sending user' do
    through_dispatcher do
      ScanSolo::Messaging::NativeTemplateSender.call(conversation: conversation, template_reference: 'scansolo_proposal', origin: 'proposal',
                                                     actor: agent)
    end

    expect(extension).to be_ai_active
    expect(takeover_events).to be_none
  end
end
