# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ScanSolo Executions API', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation,
                                          stage: :em_qualificacao)
  end
  let(:cadence_definition) do
    ScanSolo::CadenceDefinition.create!(stage: 'em_qualificacao', version: 1, offsets: [24, 48])
  end

  describe 'GET .../executions' do
    it 'surfaces cadence attempt evidence for the account (RF-62)' do
      enrollment = ScanSolo::CadenceEnrollment.create!(
        opportunity: opportunity, cadence_definition: cadence_definition, status: :active,
        current_step: 0, next_attempt_at: 1.hour.from_now
      )
      ScanSolo::CadenceAttempt.create!(
        enrollment: enrollment, step: 1, cadence_version: 1, template_reference: 'scansolo_cadence_em_qualificacao_v1_step1',
        scheduled_at: 1.hour.from_now
      )

      get "/api/v1/accounts/#{account.id}/scan_solo/executions", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      evidence = body['cadence_evidence'].find { |e| e['id'] == enrollment.id }
      expect(evidence).to be_present
      expect(evidence['attempts'].first['template_reference']).to eq('scansolo_cadence_em_qualificacao_v1_step1')
    end

    it 'surfaces a simulated failed Make callback in the error view (UI-09 AC)' do
      correlation_id = SecureRandom.uuid
      ScanSolo::MakeRequest.create!(
        account: account, action: 'proposal.generate', idempotency_key: SecureRandom.uuid,
        correlation_id: correlation_id, payload: {}, status: :failed, retry_count: 4
      )
      ScanSolo::MakeCallback.create!(
        correlation_id: correlation_id, action: 'proposal.generate', payload: {},
        applied: false, signature_valid: true, rejection_reason: 'processing_error'
      )

      get "/api/v1/accounts/#{account.id}/scan_solo/executions", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['make_errors']['dead_letters'].pluck('correlation_id')).to include(correlation_id)
      callback_error = body['make_errors']['callback_errors'].find { |c| c['correlation_id'] == correlation_id }
      expect(callback_error['rejection_reason']).to eq('processing_error')
    end

    it 'surfaces action audit records for the account (RF-46)' do
      message = create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact)
      turn = ScanSolo::AiTurn.create!(
        message: message, conversation: conversation, correlation_id: SecureRandom.uuid, invocation_status: :succeeded
      )
      agent_action = ScanSolo::AgentAction.create!(action_id: 'private_note.create', classification: :automatic, schema: {})
      execution = ScanSolo::AgentActionExecution.create!(
        action_id: agent_action.action_id, turn: turn, correlation_id: turn.correlation_id,
        idempotency_key: SecureRandom.uuid, params: {}, status: :executed
      )
      audit_event = ScanSolo::AuditLogger.record!(
        subject: execution, event_type: 'agent_action.private_note.create', correlation_id: turn.correlation_id, payload: {}
      )
      execution.update!(audit_event: audit_event)

      get "/api/v1/accounts/#{account.id}/scan_solo/executions", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['audit_events'].pluck('id')).to include(audit_event.id)
    end

    it "does not leak another account's cadence evidence" do
      other_account = create(:account, scansolo_enabled: true)
      other_contact = create(:contact, account: other_account)
      other_conversation = create(:conversation, account: other_account, contact: other_contact)
      other_opportunity = ScanSolo::PipelineOpportunity.create!(
        account: other_account, contact: other_contact, conversation: other_conversation
      )
      other_enrollment = ScanSolo::CadenceEnrollment.create!(
        opportunity: other_opportunity, cadence_definition: cadence_definition, status: :active, current_step: 0
      )

      get "/api/v1/accounts/#{account.id}/scan_solo/executions", headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['cadence_evidence'].pluck('id')).not_to include(other_enrollment.id)
    end

    it 'returns 404 for an account without ScanSolo enabled' do
      disabled_account = create(:account, scansolo_enabled: false)
      disabled_agent = create(:user, account: disabled_account, role: :agent)

      get "/api/v1/accounts/#{disabled_account.id}/scan_solo/executions",
          headers: disabled_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
