# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::AiTurn::AttemptRunner do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact,
                     content: 'Segue o documento')
  end
  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
  end
  let(:config) { ScanSolo::AiAgentConfig.published_for(account) }
  let!(:turn) do
    ScanSolo::AiTurn.create!(message: message, conversation: conversation, correlation_id: SecureRandom.uuid,
                             guardrail_outcome: { 'allowed_actions' => %w[qualification_field private_note] })
  end
  let(:pending_updates) do
    [
      { key: 'cnpj', value: '12.345.678/0001-90', source_attachment_id: nil },
      { key: 'empresa', value: 'ACME Engenharia Ltda', source_attachment_id: nil }
    ]
  end
  let(:actions) { [{ 'action_id' => 'private_note', 'params' => { 'content' => 'nota' } }] }
  let(:asked_fields) { [] }
  let(:result) do
    ScanSolo::AiTurn::ModelInvoker::Result.new(content: 'Pode me informar o bairro?', actions: actions, asked_fields: asked_fields,
                                               summary: false, provider: 'scansolo_test_mode', model: 'scansolo-mock-llm')
  end

  before do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente ScanSolo', enabled: true, allowed_inbox_ids: [inbox.id], required_qualification_fields: %w[Metragem])
    ScanSolo::AiAgent::PublishService.new(account: account).call
    opportunity.lead_state.update!(fields: { 'cidade_uf' => { 'value' => 'Rio de Janeiro / RJ', 'status' => 'confirmado' } })
  end

  def run_attempt
    described_class.call(turn: turn, message: message, config: config, result: result, opportunity: opportunity, pending_updates: pending_updates)
  end

  def ai_replies
    conversation.messages.outgoing.where(private: false)
  end

  context 'when the validator blocks the reply' do
    let(:asked_fields) { ['cidade_uf'] }

    it 'returns the violation and rolls back every change of the attempt' do
      outcome = nil

      expect { outcome = run_attempt }
        .not_to(change { [opportunity.lead_state.reload.fields, ScanSolo::LeadStateEvent.count, conversation.messages.count] })

      expect(outcome).to have_attributes(status: :blocked, violation: :confirmed_field_question)
      expect(ScanSolo::AgentActionExecution.count).to eq(0)
      expect(turn.reload).to be_pending
    end
  end

  context 'when the reply is approved' do
    it 'writes the extractions as inferido before sending the reply' do
      expect(run_attempt).to have_attributes(status: :sent, violation: nil)

      expect(opportunity.lead_state.reload.fields['cnpj']).to include('value' => '12.345.678/0001-90', 'status' => 'inferido',
                                                                      'source_message_id' => message.id)
      expect(ScanSolo::LeadStateEvent.where(key: %w[cnpj empresa]).pluck(:created_at)).to all(be <= ai_replies.sole.created_at)
      expect(ScanSolo::AgentActionExecution.sole.idempotency_key).to eq("#{turn.correlation_id}:0:private_note")
      expect(turn.reload).to have_attributes(invocation_status: 'succeeded', response_message_id: ai_replies.sole.id)
    end

    it 'concludes the qualification when an action confirms the last required field' do
      actions.replace([{ 'action_id' => 'qualification_field', 'params' => { 'fields' => { 'metragem' => '500' } } }])

      run_attempt

      expect(opportunity.lead_state.reload).to be_concluida
      expect(opportunity.reload).to be_qualificado
    end
  end

  it 'lets an action exception propagate' do
    actions.replace([{ 'action_id' => 'stage_transition', 'params' => { 'target_stage' => 'qualificado' } }])

    expect { run_attempt }.to raise_error(ScanSolo::Actions::Executor::UnregisteredActionError)
  end
end
