# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Actions::EscalateToCommercialAction do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:message) { create(:message, account: account, conversation: conversation, message_type: :incoming) }
  let!(:turn) { ScanSolo::AiTurn.create!(message: message, conversation: conversation, correlation_id: SecureRandom.uuid) }
  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end
  let(:idempotency_key) { SecureRandom.uuid }

  before do
    allow(ScanSolo::Notifications::EmailAdapter).to receive(:call)
      .and_return(ScanSolo::Notifications::Publisher::Result.new(success: true, reason: nil))
  end

  def execute(params = { conversation_id: conversation.id, reason: 'pedido_humano' }, key: idempotency_key)
    ScanSolo::Actions::Registry.call(action_id: 'escalate_to_commercial', params: params, turn: turn,
                                     correlation_id: turn.correlation_id, idempotency_key: key)
  end

  it 'is registered as an automatic action with the closed CT-02 schema' do
    execute

    action = ScanSolo::AgentAction.find_by!(action_id: 'escalate_to_commercial')
    expect(action.classification).to eq('automatic')
    expect(action.schema).to eq(described_class::SCHEMA)
  end

  it 'escalates the opportunity of the conversation and returns the CT-02 result' do
    result = execute

    expect(result.side_effect_result).to include(escalated: true, reason: 'pedido_humano')
    expect(opportunity.reload.escalation_reason).to eq('pedido_humano')
  end

  [
    { name: 'an extra key', params: ->(id) { { conversation_id: id, reason: 'negociacao', phone: '+5511999999999' } } },
    { name: 'a missing reason', params: ->(id) { { conversation_id: id } } },
    { name: 'a reason outside the 6 values', params: ->(id) { { conversation_id: id, reason: 'outro' } } }
  ].each do |example|
    it "rejects #{example[:name]}" do
      expect { execute(example[:params].call(conversation.id)) }.to raise_error(ScanSolo::Actions::Executor::InvalidParamsError)
      expect(opportunity.reload.escalated_to_commercial_at).to be_nil
    end
  end

  it 'writes 1 mark and 1 event for a repeated idempotency key' do
    freeze_time { execute }
    first_mark = opportunity.reload.escalated_to_commercial_at

    travel_to(1.hour.from_now) { execute }

    expect(opportunity.reload.escalated_to_commercial_at).to eq(first_mark)
    expect(ScanSolo::AuditEvent.where(subject: opportunity, event_type: 'commercial.escalated').count).to eq(1)
  end

  it 'does not hand off, pause the cadence or create a message (RF-06, RF-10, RF-11)' do
    expect(ScanSolo::Cadence::StopRecalculatePolicy).not_to receive(:call)
    expect(ScanSolo::Handoff::HandoffService).not_to receive(:call)

    expect { execute }.not_to change(Message, :count)
    expect(ScanSolo::ConversationExtension.resolve_for(conversation)).to be_ai_active
  end
end
