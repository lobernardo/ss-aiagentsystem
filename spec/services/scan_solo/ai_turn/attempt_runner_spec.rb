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

  describe 'RF-35: negotiation signal' do
    let(:email_inbox) { create(:channel_email, account: account, email: 'atendimento.comercial@scansolo.com.br').inbox }
    let(:pending_updates) { [] }
    let(:actions) { [{ 'action_id' => 'lead_state_update', 'params' => { 'negotiation_requested' => true } }] }
    let(:result) do
      ScanSolo::AiTurn::ModelInvoker::Result.new(content: 'Consigo fazer por R$ 11.000,00 à vista.', actions: actions, asked_fields: ['bairro'],
                                                 summary: false, provider: 'scansolo_test_mode', model: 'scansolo-mock-llm')
    end
    let(:extension) { ScanSolo::ConversationExtension.resolve_for(conversation) }

    before do
      turn.update!(guardrail_outcome: { 'allowed_actions' => %w[lead_state_update private_note] })
      ScanSolo::AiAgentConfig.draft_for!(account).update!(quote_inbox_id: email_inbox.id)
      ScanSolo::AiAgent::PublishService.new(account: account).call
    end

    def notifications
      Message.where(inbox: email_inbox, message_type: :outgoing)
    end

    context 'when the opportunity is in proposta_enviada' do
      before { opportunity.update!(stage: :proposta_enviada) }

      it 'sends the exact standard reply, moves to negociacao, hands off and publishes once after the commit' do
        ActiveRecord::Base.transaction do
          expect(run_attempt).to have_attributes(status: :sent, violation: nil)
          expect(notifications.count).to eq(0)
        end

        expect(ai_replies.sole.content).to eq('Vou verificar isso com nosso comercial. Só um momento.')
        expect(opportunity.reload).to be_negociacao
        expect(ScanSolo::PipelineStageEvent.where(opportunity: opportunity).sole)
          .to have_attributes(from_stage: 'proposta_enviada', to_stage: 'negociacao')
        expect([extension.reload.ai_control_state, conversation.messages.where(private: true).count]).to eq(['awaiting_human', 1])
        expect(notifications.count).to eq(1)
      end

      it 'stops the cadence with no attempt left scheduled' do
        definition = ScanSolo::CadenceDefinition.create!(stage: 'proposta_enviada', version: 1, offsets: [24, 72])
        ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: definition)

        run_attempt

        expect(opportunity.cadence_enrollments.where(status: :active)).to be_none
        expect(ScanSolo::CadenceAttempt.where(result: 'scheduled')).to be_none
      end

      it 'sends the standard reply instead of a model reply that quotes a price' do
        run_attempt

        expect(ai_replies.sole.content).to eq('Vou verificar isso com nosso comercial. Só um momento.')
        expect(ai_replies.sole.content).not_to include('R$')
      end

      it 'next customer message is not answered by the AI (RF-40)' do
        run_attempt
        next_message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                                        sender: contact, content: 'E então?')

        ScanSolo::AiTurn::TurnOrchestrator.call(message: next_message, llm_provider: ScanSolo::TestMode::MockLlmProvider)

        expect(ScanSolo::AiTurn.find_by!(message_id: next_message.id))
          .to have_attributes(invocation_status: 'suppressed', failure_reason: 'human_controlled')
        expect(ai_replies.count).to eq(1)
      end
    end

    context 'when the opportunity is already in negociacao with the AI active' do
      before { opportunity.update!(stage: :negociacao) }

      it 'sends the standard reply, hands off and notifies without a stage event' do
        run_attempt

        expect(ai_replies.sole.content).to eq('Vou verificar isso com nosso comercial. Só um momento.')
        expect(ScanSolo::PipelineStageEvent.where(opportunity: opportunity)).to be_none
        expect(extension.reload).to be_awaiting_human
        expect(notifications.count).to eq(1)
      end
    end

    context 'when the opportunity is still in qualification' do
      let(:result) do
        ScanSolo::AiTurn::ModelInvoker::Result.new(content: 'Pode me informar a metragem?', actions: actions, asked_fields: [],
                                                   summary: false, provider: 'scansolo_test_mode', model: 'scansolo-mock-llm')
      end

      it 'ignores the signal and sends the model reply' do
        definition = ScanSolo::CadenceDefinition.create!(stage: 'em_qualificacao', version: 1, offsets: [24, 72])
        enrollment = ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: definition)

        expect(run_attempt).to have_attributes(status: :sent)

        expect(ai_replies.sole.content).to eq('Pode me informar a metragem?')
        expect(opportunity.reload).to be_em_qualificacao
        expect(extension.reload).to be_ai_active
        expect(enrollment.reload).to be_active
        expect(ScanSolo::AuditEvent.where(event_type: 'negotiation.requested')).to be_none
        expect(notifications).to be_none
      end
    end
  end

  %w[awaiting_human human_active].each do |state|
    it "keeps the AI silent while the conversation is #{state} (RF-40)" do
      ScanSolo::ConversationExtension.resolve_for(conversation).update!(ai_control_state: state)

      ScanSolo::AiTurn::TurnOrchestrator.call(message: message, llm_provider: ScanSolo::TestMode::MockLlmProvider)

      expect(turn.reload).to have_attributes(invocation_status: 'suppressed', failure_reason: 'human_controlled')
      expect(ai_replies).to be_none
    end
  end

  it 'lets an action exception propagate' do
    actions.replace([{ 'action_id' => 'stage_transition', 'params' => { 'target_stage' => 'qualificado' } }])

    expect { run_attempt }.to raise_error(ScanSolo::Actions::Executor::UnregisteredActionError)
  end
end
