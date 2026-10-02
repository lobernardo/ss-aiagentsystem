# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::AiTurn::TurnOrchestrator do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact,
                     content: 'Quero um orçamento')
  end

  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation,
                                          stage: :em_qualificacao)
  end

  before do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente ScanSolo', enabled: true, allowed_inbox_ids: [inbox.id], required_qualification_fields: %w[Metragem])
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  def turn
    ScanSolo::AiTurn.find_by!(message_id: message.id)
  end

  def ai_replies
    conversation.messages.outgoing.where(private: false)
  end

  describe 'without any actions, the canonical guarded turn still runs end to end' do
    it 'creates one turn and sends one outbound message tagged as AI-originated' do
      described_class.call(message: message, llm_provider: ScanSolo::TestMode::MockLlmProvider)

      expect(ScanSolo::AiTurn.where(message_id: message.id).count).to eq(1)
      expect(ai_replies.sole.additional_attributes['scansolo_origin']).to eq('ai')
      expect(turn).to have_attributes(invocation_status: 'succeeded', model_provider: 'scansolo_test_mode',
                                      model_reference: 'scansolo-mock-llm')
      expect(turn.input_tokens).to be_positive
      expect(turn.latency_ms).not_to be_nil
    end
  end

  describe 'lead state RF-05 / RF-11a: attempts with one regeneration' do
    let(:calls) { [] }
    let(:responses) { [] }
    let(:provider) do
      lambda do |**kwargs|
        calls << kwargs[:payload]
        ScanSolo::TestMode::MockLlmProvider.call(**kwargs, **responses.fetch(calls.size - 1))
      end
    end

    def attach_pdf(name)
      attachment = message.attachments.new(account_id: account.id, file_type: :file)
      attachment.file.attach(io: Rails.root.join("spec/fixtures/files/scansolo/#{name}").open, filename: name, content_type: 'application/pdf')
      attachment.save!
    end

    def private_notes
      conversation.messages.where(private: true).pluck(:content)
    end

    before { opportunity.lead_state.update!(fields: { 'cidade_uf' => { 'value' => 'Rio de Janeiro / RJ', 'status' => 'confirmado' } }) }

    it 'makes 1 model call for an approved reply' do
      responses << {}

      described_class.call(message: message, llm_provider: provider)

      expect(calls.size).to eq(1)
      expect(turn).to be_succeeded
      expect(turn.context_snapshot).not_to have_key('output_regeneration')
      expect(ai_replies.count).to eq(1)
    end

    it 'regenerates once after confirmed_field_question and keeps only the 2nd attempt' do
      responses << { fixture_asked_fields: ['cidade_uf'],
                     fixture_actions: [{ 'action_id' => 'private_note', 'params' => { 'content' => 'primeira' } }] }
      responses << { fixture_actions: [{ 'action_id' => 'private_note', 'params' => { 'content' => 'segunda' } }] }

      described_class.call(message: message, llm_provider: provider)

      expect(calls.size).to eq(2)
      expect(calls.last.to_json).to include('confirmed_field_question')
      expect(turn).to be_succeeded
      expect(turn.context_snapshot['output_regeneration']).to eq('first_attempt_violation' => 'confirmed_field_question')
      expect(ai_replies.count).to eq(1)
      expect(private_notes).to eq(['segunda'])
      expect(ScanSolo::AgentActionExecution.count).to eq(1)
    end

    it 'fails with the 2nd violation and 0 changes after 2 rejections' do
      attach_pdf('lead_state_company.pdf')
      responses << { fixture_asked_fields: ['cidade_uf'] }
      responses << { fixture_asked_fields: %w[bairro area cargo] }

      expect { described_class.call(message: message, llm_provider: provider) }
        .not_to(change { [opportunity.lead_state.reload.fields, ScanSolo::LeadStateEvent.count] })

      expect(calls.size).to eq(2)
      expect(turn).to have_attributes(invocation_status: 'failed', failure_reason: 'output validation blocked: question_limit')
      expect(ai_replies.count).to eq(0)
    end

    it 'fails a price claim without regenerating' do
      responses << { fixture_response: 'O serviço custa R$ 5000' }

      described_class.call(message: message, llm_provider: provider)

      expect(calls.size).to eq(1)
      expect(turn).to have_attributes(invocation_status: 'failed', failure_reason: 'output validation blocked: price')
      expect(ai_replies.count).to eq(0)
    end

    it 'succeeds with a corrupt PDF and records the reason in the snapshot (RF-20)' do
      attach_pdf('lead_state_corrupt.pdf')
      responses << {}

      described_class.call(message: message, llm_provider: provider)

      expect(turn).to be_succeeded
      expect(turn.context_snapshot['attachment_extraction'].sole).to include('file_name' => 'lead_state_corrupt.pdf', 'extracted' => false)
      expect(turn.context_snapshot['attachment_extraction'].sole['reason']).to start_with('extraction_error: ')
    end

    it 'writes the PDF fields as inferido before the reply' do
      attach_pdf('lead_state_company.pdf')
      responses << {}

      described_class.call(message: message, llm_provider: provider)

      expect(opportunity.lead_state.reload.fields['cnpj']).to include('value' => '12.345.678/0001-90', 'status' => 'inferido')
      expect(ScanSolo::LeadStateEvent.where(key: 'cnpj').sole.created_at).to be <= ai_replies.sole.created_at
    end

    it 'fails with 0 changes on an invalid intent' do
      attach_pdf('lead_state_company.pdf')
      responses << { fixture_actions: [{ 'action_id' => 'lead_state_update', 'params' => { 'intent' => 'inexistente' } }] }

      expect { described_class.call(message: message, llm_provider: provider) }
        .not_to(change { [opportunity.lead_state.reload.attributes, ScanSolo::LeadStateEvent.count] })

      expect(turn).to be_failed
      expect(ai_replies.count).to eq(0)
    end

    it 'suppresses with 0 changes when the recheck finds the conversation human-controlled' do
      attach_pdf('lead_state_company.pdf')
      handing_over = lambda do |**kwargs|
        ScanSolo::ConversationExtension.resolve_for(conversation).update!(ai_control_state: :human_active)
        ScanSolo::TestMode::MockLlmProvider.call(**kwargs)
      end

      expect { described_class.call(message: message, llm_provider: handing_over) }
        .not_to(change { [opportunity.lead_state.reload.fields, ScanSolo::LeadStateEvent.count] })

      expect(turn).to have_attributes(invocation_status: 'suppressed', failure_reason: 'human_controlled')
      expect(turn.context_snapshot['attachment_extraction'].sole).to include('extracted' => true)
    end
  end

  describe 'RF-06: restricted_information in the model output' do
    it 'fails the turn and sends nothing' do
      ScanSolo::AiAgentConfig.draft_for!(account).update!(restricted_information: ['margem interna'])
      ScanSolo::AiAgent::PublishService.new(account: account).call
      provider = ->(**kwargs) { ScanSolo::TestMode::MockLlmProvider.call(**kwargs, fixture_response: 'Nossa Margem Interna é 40%') }

      described_class.call(message: message, llm_provider: provider)

      expect(turn).to have_attributes(invocation_status: 'failed', failure_reason: 'output validation blocked: restricted_information')
      expect(ai_replies.count).to eq(0)
    end
  end

  describe 'RF-07: any exception after the turn row exists ends the turn failed and is reported once' do
    let(:tracker) { instance_double(ChatwootExceptionTracker, capture_exception: nil) }

    let(:provider_requesting_stage_move) do
      actions = [{ 'action_id' => 'stage_transition', 'params' => { 'target_stage' => 'qualificado' } }]
      ->(**kwargs) { ScanSolo::TestMode::MockLlmProvider.call(**kwargs, fixture_actions: actions) }
    end

    before { allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker) }

    {
      'context' => -> { allow(ScanSolo::AiTurn::ContextAssembler).to receive(:call).and_raise(StandardError, 'boom') },
      'retrieval' => -> { allow(ScanSolo::Knowledge::RetrievalService).to receive(:call).and_raise(StandardError, 'boom') },
      'guardrail' => -> { allow(ScanSolo::AiTurn::InputGuardrail).to receive(:call).and_raise(StandardError, 'boom') },
      'model' => -> { allow(ScanSolo::TestMode::MockLlmProvider).to receive(:call).and_raise(StandardError, 'boom') },
      'validation' => -> { allow(ScanSolo::AiTurn::OutputValidator).to receive(:call).and_raise(StandardError, 'boom') },
      'actions' => -> { allow(ScanSolo::Actions::Registry).to receive(:call).and_raise(StandardError, 'boom') },
      'send' => -> { allow(ScanSolo::AiTurn::ResponseSender).to receive(:call).and_raise(StandardError, 'boom') }
    }.each do |stage, failure|
      it "marks the turn failed when the #{stage} stage raises" do
        instance_exec(&failure)

        described_class.call(message: message, llm_provider: provider_requesting_stage_move)

        expect(turn).to have_attributes(invocation_status: 'failed', failure_reason: 'StandardError: boom')
        expect(ChatwootExceptionTracker).to have_received(:new)
          .with(an_instance_of(StandardError), account: account, tags: { scansolo_correlation_id: turn.correlation_id }).once
        expect(tracker).to have_received(:capture_exception).once
        expect(ai_replies.count).to eq(0)
        expect(opportunity.reload).to be_em_qualificacao
      end
    end

    it 'redacts secret-shaped values from the recorded failure reason' do
      allow(ScanSolo::AiTurn::ContextAssembler).to receive(:call).and_raise(StandardError, 'key sk-live_abcdefghijklmnop leaked')

      described_class.call(message: message, llm_provider: ScanSolo::TestMode::MockLlmProvider)

      expect(turn.failure_reason).to eq('StandardError: key [REDACTED] leaked')
    end

    it 'brings an attachment-only incoming message to a terminal state' do
      attachment_only = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                                         sender: contact, content: nil)

      described_class.call(message: attachment_only, llm_provider: ScanSolo::TestMode::MockLlmProvider)

      expect(ScanSolo::AiTurn.find_by!(message_id: attachment_only.id)).to be_succeeded
    end
  end

  describe 'RF-09: idempotent re-runs' do
    %i[succeeded suppressed failed].each do |status|
      it "is a no-op for a #{status} turn" do
        existing = ScanSolo::AiTurn.create!(message: message, conversation: conversation, correlation_id: SecureRandom.uuid,
                                            invocation_status: status)

        expect { described_class.call(message: message, llm_provider: ScanSolo::TestMode::MockLlmProvider) }
          .not_to(change { [existing.reload.attributes, ai_replies.count] })
      end
    end

    it 'resumes a pending turn without a response on the same row and correlation id' do
      pending_turn = ScanSolo::AiTurn.create!(message: message, conversation: conversation, correlation_id: SecureRandom.uuid)

      described_class.call(message: message, llm_provider: ScanSolo::TestMode::MockLlmProvider)

      resumed = ScanSolo::AiTurn.where(message_id: message.id).sole
      expect(resumed).to have_attributes(id: pending_turn.id, invocation_status: 'succeeded', correlation_id: pending_turn.correlation_id)
      expect(ai_replies.count).to eq(1)
    end
  end

  describe 'RF-10: eligibility before the model call' do
    it 'suppresses without invoking the model while the conversation is human-controlled' do
      ScanSolo::ConversationExtension.resolve_for(conversation).update!(ai_control_state: :human_active)
      allow(ScanSolo::TestMode::MockLlmProvider).to receive(:call).and_call_original

      described_class.call(message: message, llm_provider: ScanSolo::TestMode::MockLlmProvider)

      expect(turn).to have_attributes(invocation_status: 'suppressed', failure_reason: 'human_controlled')
      expect(ScanSolo::TestMode::MockLlmProvider).not_to have_received(:call)
    end

    it 'suppresses a trigger that is no longer the latest incoming message before invoking the model (RF-11)' do
      message
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact)

      described_class.call(message: message, llm_provider: ScanSolo::TestMode::MockLlmProvider)

      expect(turn).to have_attributes(invocation_status: 'suppressed', failure_reason: 'superseded')
    end
  end

  describe 'RF-28: the reply-completeness rule after the turn' do
    let(:definition) { ScanSolo::CadenceDefinition.create!(stage: 'em_qualificacao', version: 1, offsets: [24, 48, 72]) }
    let!(:enrollment) do
      travel_to(1.hour.ago) { ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: definition) }
    end

    it 'cancels every scheduled attempt once all required fields are present' do
      opportunity.lead_state.update!(fields: { 'metragem' => { 'value' => '5000', 'status' => 'confirmado' } })

      described_class.call(message: message, llm_provider: ScanSolo::TestMode::MockLlmProvider)

      expect(ScanSolo::CadenceAttempt.scheduled.count).to eq(0)
    end

    # RF-43 changes this expectation (RNF-11): the next attempt is interrupted by the
    # listener (ScanSolo::Cadence::ReplyInterruptionService), not by the turn.
    it 'cancels no attempt on a partial reply' do
      described_class.call(message: message, llm_provider: ScanSolo::TestMode::MockLlmProvider)

      expect(enrollment.attempts.order(:step).pluck(:result)).to eq(%w[scheduled scheduled scheduled])
    end

    it 'leaves an enrollment created by the triggering message itself untouched' do
      ScanSolo::Cadence::LifecycleService.cancel!(enrollment)
      fresh = ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: definition)
      fresh.update!(created_at: message.created_at)

      described_class.call(message: message, llm_provider: ScanSolo::TestMode::MockLlmProvider)

      expect(fresh.attempts.pluck(:result).uniq).to eq(['scheduled'])
    end
  end
end
