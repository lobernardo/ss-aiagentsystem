# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ScanSolo AI Turns API', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:message) do
    create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact)
  end

  let(:response_message) do
    create(:message, account: account, conversation: conversation, message_type: :outgoing, status: :delivered)
  end
  let(:knowledge_evidence) { [{ 'source_id' => 3, 'source_title' => 'Garantia', 'chunk_id' => 9, 'similarity_score' => 0.87 }] }
  let!(:turn) do
    ScanSolo::AiTurn.create!(
      message: message, conversation: conversation, correlation_id: SecureRandom.uuid, response_message: response_message,
      invocation_status: :succeeded, guardrail_outcome: { blocked: false }, action_evidence: [], knowledge_evidence: knowledge_evidence,
      model_provider: 'openai', model_reference: 'gpt-4.1-mini', input_tokens: 812, output_tokens: 96, latency_ms: 1430,
      context_snapshot: { 'knowledge_context' => [] }
    )
  end

  describe 'GET .../ai_turns' do
    it 'lists turns for the account' do
      get "/api/v1/accounts/#{account.id}/scan_solo/ai_turns", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.map { |t| t['id'] }).to include(turn.id)
    end

    it 'exposes provider, model, tokens and latency of a succeeded turn (RF-59)' do
      get "/api/v1/accounts/#{account.id}/scan_solo/ai_turns", headers: agent.create_new_auth_token, as: :json

      listed = response.parsed_body.find { |t| t['id'] == turn.id }
      expect(listed).to include('model_provider' => 'openai', 'model_reference' => 'gpt-4.1-mini', 'input_tokens' => 812,
                                'output_tokens' => 96, 'latency_ms' => 1430, 'failure_reason' => nil)
    end
  end

  describe 'GET .../ai_turns/:correlation_id' do
    it 'is queryable by correlation id and returns guardrail/knowledge/action evidence' do
      get "/api/v1/accounts/#{account.id}/scan_solo/ai_turns/#{turn.correlation_id}",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['correlation_id']).to eq(turn.correlation_id)
      expect(body).to include('guardrail_outcome', 'action_evidence')
      expect(body['knowledge_evidence']).to eq(knowledge_evidence)
      expect(body['response_delivery_status']).to eq('delivered')
    end

    it 'returns a null delivery status for a turn without a response message' do
      turn.update!(response_message: nil, invocation_status: :suppressed, failure_reason: 'human_controlled')

      get "/api/v1/accounts/#{account.id}/scan_solo/ai_turns/#{turn.correlation_id}",
          headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body).to include('response_delivery_status' => nil, 'failure_reason' => 'human_controlled')
    end

    it 'returns 404 for a correlation id belonging to another account' do
      other_account = create(:account, scansolo_enabled: true)
      other_contact = create(:contact, account: other_account)
      other_conversation = create(:conversation, account: other_account, contact: other_contact)
      other_message = create(:message, account: other_account, conversation: other_conversation,
                                       message_type: :incoming, sender: other_contact)
      other_turn = ScanSolo::AiTurn.create!(message: other_message, conversation: other_conversation,
                                            correlation_id: SecureRandom.uuid, invocation_status: :succeeded)

      get "/api/v1/accounts/#{account.id}/scan_solo/ai_turns/#{other_turn.correlation_id}",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
