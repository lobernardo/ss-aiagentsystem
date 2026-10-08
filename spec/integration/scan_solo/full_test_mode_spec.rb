# frozen_string_literal: true

require 'rails_helper'

# T76 / RF-91 / RNF-03: capstone integration suite proving the ScanSolo
# isolated test mode composes correctly end to end across every module this
# plan builds. Every collaborator exercised here already has its own unit or
# request spec; this suite instead wires the real objects together (no
# internal ScanSolo service is stubbed -- only the true external boundaries:
# LLM, embeddings, WhatsApp/Meta transport and Make) to prove the modules
# actually compose, and that the whole thing runs to completion with zero
# production credential and zero real outbound request.
#
# Each example below is labelled with the description Section 20
# acceptance-outcome item (1-19) it demonstrates; see
# docs/architecture/SCANSOLO_ACCEPTANCE_TRACEABILITY.md (T77) for the full
# item-by-item mapping to every automated test that covers it, including the
# dedicated unit/request specs this suite deliberately does not duplicate.
RSpec.describe 'ScanSolo full isolated test mode', :scansolo_full_test_mode do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  def publish_agent_config!(**attrs)
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!({ name: 'Agente ScanSolo', enabled: true, allowed_inbox_ids: [conversation.inbox_id] }.merge(attrs))
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  describe 'item 1: a fake inbound message persists in the native Chatwoot flow' do
    it 'creates a real Message row that appears in the conversation history' do
      message = create(:message, account: account, conversation: conversation, message_type: :incoming,
                                 sender: contact, content: 'Oi, quero saber mais')

      expect(conversation.messages.reload).to include(message)
    end
  end

  describe 'item 2: the AI processes one turn exactly once per inbound message' do
    before { publish_agent_config! }

    it 'produces exactly one AiTurn and one outbound message even when the job runs twice (Sidekiq retry)' do
      message = create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact)

      2.times { ScanSolo::AiTurnJob.new.perform(message.id, llm_provider: ScanSolo::TestMode::MockLlmProvider) }

      expect(ScanSolo::AiTurn.where(message_id: message.id).count).to eq(1)
      expect(conversation.messages.outgoing.count).to eq(1)
    end
  end

  describe 'item 3: the agent uses canonical conversation history' do
    before { publish_agent_config! }

    it 'threads persisted native message history into the turn context snapshot' do
      create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact,
                       content: 'primeira mensagem')
      message = create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact,
                                 content: 'segunda mensagem')

      ScanSolo::AiTurnJob.new.perform(message.id, llm_provider: ScanSolo::TestMode::MockLlmProvider)

      history = ScanSolo::AiTurn.find_by(message_id: message.id).context_snapshot['conversation_history']
      expect(history.map { |m| m['content'] }).to include('primeira mensagem', 'segunda mensagem')
    end
  end

  describe 'item 4: RAG retrieval returns evidence' do
    let(:user) { create(:user, account: account, role: :agent) }
    let(:source) do
      ScanSolo::KnowledgeSource.create!(account: account, added_by: user, source_type: :faq, origin: 'manual',
                                        content: 'Qual o horário de atendimento?')
    end

    it 'returns a result traceable to its originating knowledge source after ingestion' do
      ScanSolo::Knowledge::IngestionService.call(source: source, embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider)

      response = ScanSolo::Knowledge::RetrievalService.call(
        account: account, query: 'horário', embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider
      )

      expect(response[:failure_reason]).to be_nil
      expect(response[:results]).not_to be_empty
      expect(response[:results].first.source_id).to eq(source.id)
    end
  end

  describe 'item 5: guardrails/action permissions are enforced' do
    let(:message) { create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact) }
    let!(:turn) { ScanSolo::AiTurn.create!(message: message, conversation: conversation, correlation_id: SecureRandom.uuid) }

    before do
      ScanSolo::AgentAction.create!(
        action_id: 'test_note', classification: :automatic,
        schema: { 'type' => 'object', 'properties' => { 'note' => { 'type' => 'string' } },
                  'required' => ['note'], 'additionalProperties' => false }
      )
    end

    it 'rejects a free-form/unregistered parameter before any side effect executes' do
      side_effect_called = false

      expect do
        ScanSolo::Actions::Executor.call(
          action_id: 'test_note', params: { note: 'ok', command: 'rm -rf /' },
          correlation_id: turn.correlation_id, idempotency_key: SecureRandom.uuid, turn: turn
        ) { |_p| side_effect_called = true }
      end.to raise_error(ScanSolo::Actions::Executor::InvalidParamsError)

      expect(side_effect_called).to be false
    end
  end

  describe 'item 6: pipeline state changes correctly and the Kanban API reflects it' do
    let!(:opportunity) do
      ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
    end
    let(:agent) { create(:user, account: account, role: :agent) }

    it 'applies the transition through the API and exposes it on a subsequent read' do
      base_path = "/api/v1/accounts/#{account.id}/scan_solo/pipeline_opportunities/#{opportunity.id}"

      post "#{base_path}/stage_transitions", params: { target_stage: 'em_contato' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(opportunity.reload.stage).to eq('em_contato')

      get base_path, headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['stage']).to eq('em_contato')
      expect(response.parsed_body['stage_history'].length).to eq(1)
    end
  end

  describe 'item 7: AI handoff creates a private summary and suppresses further AI' do
    let(:agent) { create(:user, account: account, role: :agent) }

    before do
      ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
      publish_agent_config!(required_qualification_fields: %w[budget])
      create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact)
    end

    it 'creates exactly one private note and blocks the next automatic AI reply' do
      ScanSolo::Handoff::HandoffService.call(conversation: conversation, reason: 'cliente pediu humano', actor: agent)

      expect(conversation.messages.where(private: true).count).to eq(1)
      expect(ScanSolo::ConversationExtension.resolve_for(conversation)).to be_awaiting_human

      next_message = create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact)
      ScanSolo::AiTurnJob.new.perform(next_message.id, llm_provider: ScanSolo::TestMode::MockLlmProvider)

      expect(ScanSolo::AiTurn.find_by(message_id: next_message.id)).to be_suppressed
      expect(conversation.messages.outgoing.where(private: false).count).to eq(0)
    end
  end

  describe 'item 8: an authorized return to AI works' do
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:conversation) { create(:conversation, account: account, contact: contact, assignee: agent) }

    it 'restores ai_active for the assigned agent through the handoff API' do
      base_path = "/api/v1/accounts/#{account.id}/scan_solo/conversations/#{conversation.display_id}"
      post "#{base_path}/handoff", params: { reason: 'transferência' }, headers: agent.create_new_auth_token, as: :json
      expect(ScanSolo::ConversationExtension.resolve_for(conversation)).to be_human_active

      post "#{base_path}/return_to_ai", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(ScanSolo::ConversationExtension.resolve_for(conversation)).to be_ai_active
    end
  end

  describe 'item 9: Novo Lead cadence schedules +2h/+24h/+48h/+96h correctly' do
    let!(:opportunity) do
      ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
    end
    let(:cadence_definition) { ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2, 24, 48, 96]) }

    it 'creates the four attempts at the documented offsets from enrollment' do
      enrolled_at = Time.zone.local(2026, 2, 2, 9, 0, 0)

      enrollment = travel_to(enrolled_at) do
        ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: cadence_definition)
      end

      offsets_in_hours = enrollment.attempts.order(:scheduled_at).map { |a| ((a.scheduled_at - enrolled_at) / 1.hour).round }
      expect(offsets_in_hours).to eq([2, 24, 48, 96])
    end
  end

  describe 'item 10: a customer response cancels/recalculates applicable pending cadence work' do
    let!(:opportunity) do
      ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
    end
    let(:cadence_definition) { ScanSolo::CadenceDefinition.create!(stage: 'em_qualificacao', version: 1, offsets: [24, 48]) }
    let!(:enrollment) { ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: cadence_definition) }

    before { publish_agent_config!(required_qualification_fields: ['Área']) }

    it 'stops the whole pending schedule once the customer supplies every required field' do
      ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state)
                                 .apply_field!(key: 'area', value: '800 m²', status: 'confirmado', source_message_id: nil)

      result = ScanSolo::Cadence::ReplyCompletenessDetector.call(opportunity: opportunity)

      expect(result).to be_complete
      expect(enrollment.reload).to be_cancelled
    end
  end

  describe 'item 11: human takeover pauses/stops applicable cadence work' do
    let!(:opportunity) do
      ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
    end
    let(:cadence_definition) { ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2, 24]) }
    let!(:enrollment) { ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: cadence_definition) }
    let(:agent) { create(:user, account: account, role: :agent) }

    it 'pauses a scheduled-but-unsent attempt and leaves an already-sent one untouched' do
      sent_attempt = enrollment.attempts.order(:scheduled_at).first
      ScanSolo::Cadence::AttemptEvidenceRecorder.record_sent!(sent_attempt)
      pending_attempt = enrollment.attempts.order(:scheduled_at).second

      ScanSolo::Handoff::TakeoverService.call(conversation: conversation, reason: 'cliente pediu humano', actor: agent)

      expect(enrollment.reload).to be_paused
      expect(sent_attempt.reload).to be_sent
      expect(pending_attempt.reload).to be_scheduled
    end
  end

  describe 'item 12: a stage change recalculates/replaces cadence according to policy' do
    let!(:opportunity) do
      ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
    end
    let(:cadence_definition) { ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2, 24]) }
    let!(:enrollment) { ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: cadence_definition) }

    it 'stops the current cadence when the opportunity moves to another stage' do
      ScanSolo::Pipeline::StageTransitionService.new(opportunity: opportunity, target_stage: :em_contato).call

      expect(enrollment.reload).to be_cancelled
    end
  end

  describe 'item 13: a fake Meta template send runs through the native Chatwoot messaging path' do
    it 'creates the outbound message via conversation.messages.create!, never a parallel WhatsApp client' do
      result = perform_enqueued_jobs do
        ScanSolo::Messaging::NativeTemplateSender.call(
          conversation: conversation, template_reference: 'scansolo_cadence_novo_lead_v1_step1', origin: 'cadence',
          template_params: { category: 'UTILITY', language: 'pt_BR' }
        )
      end

      expect(result.message).to be_persisted
      expect(result.message).to be_outgoing
      expect(conversation.messages.reload).to include(result.message)
    end
  end

  describe 'item 14: mock proposal generation runs through a Make-compatible contract' do
    let!(:opportunity) do
      ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
    end

    # RF-25 (RNF-11): generation needs the validated quote reply.
    it 'generates a proposal version via the registered mock provider' do
      quote_request = ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid, status: :replied)
      version = ScanSolo::Proposal::GenerateService.call(opportunity: opportunity, quote_request: quote_request, correlation_id: SecureRandom.uuid)

      expect(version).to be_awaiting_approval
      expect(version.value).to eq(ScanSolo::Proposal::MockProvider::DEFAULT_VALUE)
      expect(version.artifact_url).to be_present
    end

    it 'round-trips an outbound Make request and its signed inbound callback with zero real HTTP call' do
      scenario_url = 'https://hook.make.example/scenario-webhook'
      inbound_secret = 'make-inbound-secret'
      correlation_id = SecureRandom.uuid

      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :scenario_url).and_return(scenario_url)
      allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :secret).and_return('make-outbound-secret')
      allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :inbound_signing_secret).and_return(inbound_secret)
      stub_request(:post, scenario_url).to_return(status: 200, body: '{}')

      version = ScanSolo::Proposal.create!(opportunity: opportunity).versions.create!(generate_correlation_id: correlation_id)
      make_request = ScanSolo::Proposal::MakeProvider.request_generation(proposal_version: version, correlation_id: correlation_id)
      expect(make_request).to be_sent
      expect(a_request(:post, scenario_url)).to have_been_made.once

      callback_body = {
        correlation_id: correlation_id, idempotency_key: correlation_id, action: 'proposal.generate', status: 'success',
        result: { proposal_version_id: version.id, artifact_url: 'https://make.example/1.pdf',
                  total_value: 1800.0, currency: 'BRL', valid_until: 1.week.from_now.iso8601 }
      }.to_json
      signature = OpenSSL::HMAC.hexdigest('SHA256', inbound_secret, callback_body)

      post '/webhooks/scan_solo/make', params: callback_body,
                                       headers: { 'CONTENT_TYPE' => 'application/json', 'X-Make-Signature' => signature }

      expect(response).to have_http_status(:ok)
      expect(make_request.reload).to be_completed
      expect(version.reload).to have_attributes(status: 'awaiting_approval', value: BigDecimal(1800))
    end
  end

  describe 'item 15: a proposal cannot report sent before successful send evidence' do
    let!(:opportunity) do
      ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
    end
    let(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
    let(:agent) { create(:user, account: account) }

    before { publish_agent_config!(require_proposal_approval: false) }

    it 'leaves the version non-sent on a simulated send failure' do
      version = proposal.versions.create!(status: :generated, value: 1000, currency: 'BRL', artifact_url: 'https://x.test/a.pdf')
      failing_provider = Class.new do
        def self.request_send(proposal_version:, correlation_id:, **)
          ScanSolo::Proposal::CallbackHandler.apply_send_result!(
            proposal_version: proposal_version, correlation_id: correlation_id, success: false, failure_reason: 'mock_send_failed'
          )
        end
      end

      ScanSolo::Proposal::SendService.call(
        proposal_version: version, correlation_id: SecureRandom.uuid, conversation: conversation, actor: agent, provider: failing_provider
      )

      expect(version.reload).not_to be_sent
      expect(version.status).to eq('failed')
    end
  end

  describe 'item 16: a successful proposal send moves stage and enrolls configured cadence' do
    let!(:opportunity) do
      ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
    end
    let(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
    let(:agent) { create(:user, account: account) }

    before do
      publish_agent_config!(require_proposal_approval: false)
      ScanSolo::CadenceDefinition.create!(stage: 'proposta_enviada', version: 1, offsets: [24, 72, 168])
    end

    it 'transitions the opportunity and creates an active post-proposal cadence enrollment' do
      version = proposal.versions.create!(status: :generated, value: 1000, currency: 'BRL', artifact_url: 'https://x.test/a.pdf')

      perform_enqueued_jobs(only: EventDispatcherJob) do
        ScanSolo::Proposal::SendService.call(
          proposal_version: version, correlation_id: SecureRandom.uuid, conversation: conversation, actor: agent,
          provider: ScanSolo::Proposal::MockProvider
        )
      end

      expect(opportunity.reload).to be_proposta_enviada
      expect(opportunity.cadence_enrollments.active.count).to eq(1)
    end
  end

  describe 'item 17: duplicate jobs/webhooks/callbacks do not duplicate side effects' do
    it 'AiTurnJob: retrying the same message id produces exactly one turn and one outbound message' do
      publish_agent_config!
      message = create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact)

      2.times { ScanSolo::AiTurnJob.new.perform(message.id, llm_provider: ScanSolo::TestMode::MockLlmProvider) }

      expect(ScanSolo::AiTurn.where(message_id: message.id).count).to eq(1)
      expect(conversation.messages.outgoing.count).to eq(1)
    end

    it 'CadenceDueAttemptJob: re-running an already-sent attempt sends nothing further' do
      opportunity = ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation,
                                                          stage: :novo_lead)
      cadence_definition = ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2])
      enrollment = ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: cadence_definition)
      attempt = enrollment.attempts.first
      morning = ActiveSupport::TimeZone['America/Sao_Paulo'].local(2026, 1, 5, 10, 0, 0)
      attempt.update!(scheduled_at: morning)

      travel_to(morning + 1.minute) do
        perform_enqueued_jobs { ScanSolo::CadenceDueAttemptJob.process_attempt!(attempt.reload) }

        expect do
          perform_enqueued_jobs { ScanSolo::CadenceDueAttemptJob.process_attempt!(attempt.reload) }
        end.not_to(change { Message.where(conversation_id: conversation.id).count })
      end
    end

    it 'Make callback: replaying the same signed payload does not reapply the side effect' do
      inbound_secret = 'make-inbound-secret'
      correlation_id = SecureRandom.uuid
      opportunity = ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
      version = ScanSolo::Proposal.create!(opportunity: opportunity).versions.create!(generate_correlation_id: correlation_id)
      make_request = ScanSolo::MakeRequest.create!(
        account: account, correlation_id: correlation_id, idempotency_key: SecureRandom.uuid,
        action: 'proposal.generate', payload: { proposal_version_id: version.id }, status: :sent
      )
      body = { correlation_id: correlation_id, idempotency_key: make_request.idempotency_key, action: 'proposal.generate',
               status: 'success',
               result: { proposal_version_id: version.id, artifact_url: 'https://make.example/1.pdf',
                         total_value: 1800.0, currency: 'BRL', valid_until: 1.week.from_now.iso8601 } }.to_json

      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :inbound_signing_secret).and_return(inbound_secret)
      signature = OpenSSL::HMAC.hexdigest('SHA256', inbound_secret, body)
      headers = { 'CONTENT_TYPE' => 'application/json', 'X-Make-Signature' => signature }

      post '/webhooks/scan_solo/make', params: body, headers: headers
      expect(response).to have_http_status(:ok)

      expect do
        post '/webhooks/scan_solo/make', params: body, headers: headers
      end.not_to(change { version.reload.attributes })
      expect(response).to have_http_status(:ok)
      expect(ScanSolo::MakeCallback.where(correlation_id: correlation_id).count).to eq(1)
      expect(make_request.reload).to be_completed
    end
  end

  describe 'item 18: relevant operations are auditable' do
    it 'links an executed action to an AuditEvent surfaced by the executions API' do
      agent = create(:user, account: account, role: :agent)
      message = create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact)
      turn = ScanSolo::AiTurn.create!(message: message, conversation: conversation, correlation_id: SecureRandom.uuid)
      ScanSolo::AgentAction.create!(action_id: 'audited_action', classification: :automatic, schema: { 'type' => 'object' })

      result = ScanSolo::Actions::Executor.call(
        action_id: 'audited_action', params: {}, correlation_id: turn.correlation_id,
        idempotency_key: SecureRandom.uuid, turn: turn
      ) { |_p| 'ok' }

      audit_event = result.execution.audit_event
      expect(audit_event.correlation_id).to eq(turn.correlation_id)

      get "/api/v1/accounts/#{account.id}/scan_solo/executions", headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['audit_events'].pluck('id')).to include(audit_event.id)
    end
  end

  describe 'item 19: no production token/key/number is required for the test suite' do
    it 'ran this whole suite without any production credential and made zero real outbound request' do # rubocop:disable RSpec/NoExpectationExample
      scansolo_assert_no_production_credentials_present!
      scansolo_assert_zero_real_outbound_requests!
    end
  end
end
