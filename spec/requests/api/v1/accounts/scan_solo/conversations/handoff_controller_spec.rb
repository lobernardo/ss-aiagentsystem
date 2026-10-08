# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ScanSolo Conversation Handoff API', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:assigned_agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact, assignee: assigned_agent) }

  let(:base_path) { "/api/v1/accounts/#{account.id}/scan_solo/conversations/#{conversation.display_id}" }

  describe 'GET .../control_state' do
    it 'returns the resolvable control state for the conversation' do
      get "#{base_path}/control_state", headers: assigned_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['conversation_id']).to eq(conversation.id)
      expect(response.parsed_body['ai_control_state']).to eq('ai_active')
    end
  end

  describe 'POST .../handoff (takeover)' do
    it 'applies takeover for the assigned agent, creating the private note and setting human_active' do
      post "#{base_path}/handoff", params: { reason: 'Cliente pediu para falar com humano' },
                                    headers: assigned_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['ai_control_state']).to eq('human_active')
      expect(conversation.messages.where(private: true).count).to eq(1)
    end

    it 'applies takeover for an account administrator' do
      post "#{base_path}/handoff", params: { reason: 'Assumindo conversa' },
                                    headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['ai_control_state']).to eq('human_active')
    end

    it 'rejects takeover from a user who is neither the assigned agent nor an administrator' do
      post "#{base_path}/handoff", params: { reason: 'Tentando assumir' },
                                    headers: other_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(ScanSolo::ConversationExtension.resolve_for(conversation)).to be_ai_active
    end

    it 'is idempotent: a repeated takeover command leaves the same state with no duplicate audit entry' do
      headers = assigned_agent.create_new_auth_token

      post "#{base_path}/handoff", params: { reason: 'primeira vez' }, headers: headers, as: :json
      expect(response).to have_http_status(:success)

      expect do
        post "#{base_path}/handoff", params: { reason: 'segunda vez' }, headers: headers, as: :json
      end.to not_change(ScanSolo::AuditEvent, :count)
         .and not_change { conversation.messages.where(private: true).count }

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['ai_control_state']).to eq('human_active')
    end
  end

  describe 'POST .../return_to_ai' do
    before do
      post "#{base_path}/handoff", params: { reason: 'transferência' }, headers: assigned_agent.create_new_auth_token, as: :json
    end

    it 'is rejected for a user who is neither the assigned agent nor an administrator' do
      post "#{base_path}/return_to_ai", headers: other_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(ScanSolo::ConversationExtension.resolve_for(conversation)).to be_human_active
    end

    it 'is applied for the assigned agent' do
      post "#{base_path}/return_to_ai", headers: assigned_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['ai_control_state']).to eq('ai_active')
    end

    it 'is applied for an account administrator' do
      post "#{base_path}/return_to_ai", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['ai_control_state']).to eq('ai_active')
    end

    it 'is idempotent: a repeated return-to-ai command produces no duplicate audit entry' do
      headers = assigned_agent.create_new_auth_token

      post "#{base_path}/return_to_ai", headers: headers, as: :json
      expect(response).to have_http_status(:success)

      expect do
        post "#{base_path}/return_to_ai", headers: headers, as: :json
      end.to not_change(ScanSolo::AuditEvent, :count)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['ai_control_state']).to eq('ai_active')
    end
  end
end
