require 'rails_helper'

RSpec.describe ScanSolo::Actions::LeadStateUpdateAction do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) { ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao) }
  let(:first_message) { create(:message, account: account, conversation: conversation, message_type: :incoming) }
  let(:second_message) { create(:message, account: account, conversation: conversation, message_type: :incoming) }
  let(:first_turn) { ScanSolo::AiTurn.create!(message: first_message, conversation: conversation, correlation_id: SecureRandom.uuid) }
  let(:second_turn) { ScanSolo::AiTurn.create!(message: second_message, conversation: conversation, correlation_id: SecureRandom.uuid) }
  let(:lead_state) { opportunity.lead_state.reload }

  def invoke(params, turn: first_turn)
    ScanSolo::Actions::Registry.call(action_id: 'lead_state_update', params: { opportunity_id: opportunity.id, **params },
                                     correlation_id: turn.correlation_id, idempotency_key: SecureRandom.uuid, turn: turn)
  end

  it 'is an automatic action with a closed schema' do
    expect(described_class::CLASSIFICATION).to eq(:automatic)
    expect(described_class::SCHEMA).to include('additionalProperties' => false, 'required' => ['opportunity_id'])
  end

  it 'records each intent change in the history with its source message (RF-14)' do
    invoke({ intent: 'orcamento' })
    invoke({ intent: 'convite_cotacao' }, turn: second_turn)

    expect(lead_state.intent).to eq('convite_cotacao')
    expect(lead_state.events.where(subject: 'intent').order(:id).pluck(:previous_value, :new_value, :source_message_id))
      .to eq([[nil, 'orcamento', first_message.id], ['orcamento', 'convite_cotacao', second_message.id]])
  end

  it 'rejects an intent outside the list' do
    expect { invoke({ intent: 'xyz' }) }.to(raise_error { |error| expect(error.class.name).to eq('ScanSolo::Actions::Executor::InvalidParamsError') })
    expect(lead_state.intent).to be_nil
  end

  it 'rejects an extra parameter' do
    expect { invoke({ intent: 'orcamento', stage: 'ganho' }) }
      .to(raise_error { |error| expect(error.class.name).to eq('ScanSolo::Actions::Executor::InvalidParamsError') })
  end

  it 'rejects a next action outside the list (RF-23)' do
    expect { invoke({ next_action: 'enviar_email' }) }
      .to(raise_error { |error| expect(error.class.name).to eq('ScanSolo::Actions::Executor::InvalidParamsError') })
  end

  it 'records the next action with its origin (RF-23)' do
    result = invoke({ next_action: 'proposta' })

    expect(lead_state).to have_attributes(next_action: 'proposta', next_action_source_message_id: first_message.id)
    expect(lead_state.next_action_recorded_at).to be_present
    expect(result.side_effect_result).to include(opportunity_id: opportunity.id, next_action: 'proposta')
  end

  it 'records an authorized action with its source message (RF-24)' do
    invoke({ authorized_action: 'proposta', interpretation_risk: true })

    expect(lead_state.authorized_actions).to contain_exactly(include('action' => 'proposta', 'source_message_id' => first_message.id))
  end

  it 'returns negotiation_requested only as evidence, with no write or side effect (RF-35)' do
    extension = ScanSolo::ConversationExtension.resolve_for(conversation)
    first_turn

    result = nil
    expect { result = invoke({ negotiation_requested: true }) }
      .not_to(change { [lead_state.attributes, extension.reload.ai_control_state, conversation.messages.count, ScanSolo::PipelineStageEvent.count] })

    expect(result.side_effect_result).to eq(opportunity_id: opportunity.id, negotiation_requested: true)
    expect(opportunity.reload).to be_em_qualificacao
  end

  it 'rejects a non-boolean negotiation_requested' do
    expect { invoke({ negotiation_requested: 'sim' }) }
      .to(raise_error { |error| expect(error.class.name).to eq('ScanSolo::Actions::Executor::InvalidParamsError') })
  end

  it 'runs no side effect when recording atendimento_humano (RF-23)' do
    extension = ScanSolo::ConversationExtension.resolve_for(conversation)
    first_turn

    expect { invoke({ next_action: 'atendimento_humano' }) }
      .not_to(change { [extension.reload.ai_control_state, conversation.messages.count, ScanSolo::PipelineStageEvent.count] })
    expect(lead_state.next_action).to eq('atendimento_humano')
    expect(opportunity.reload.stage).to eq('em_qualificacao')
  end
end
