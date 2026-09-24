# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ScanSolo AI Agent Config API', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:agent) { create(:user, account: account, role: :administrator) }
  let(:base_path) { "/api/v1/accounts/#{account.id}/scan_solo/ai_agent_config" }

  describe 'GET .../ai_agent_config' do
    it 'auto-creates and returns the draft, with a null published value before any publish' do
      get base_path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['draft']['status']).to eq('draft')
      expect(body['published']).to be_nil
    end

    it 'returns the published config distinctly from the draft once published' do
      put "#{base_path}/draft", params: { name: 'Agente v1', enabled: true }, headers: agent.create_new_auth_token, as: :json
      post "#{base_path}/publish", headers: agent.create_new_auth_token, as: :json

      get base_path, headers: agent.create_new_auth_token, as: :json

      body = response.parsed_body
      expect(body['published']['name']).to eq('Agente v1')
      expect(body['published']['status']).to eq('published')
    end
  end

  describe 'PUT .../ai_agent_config/draft' do
    it 'updates the draft without affecting the live/published config' do
      put "#{base_path}/draft", params: { name: 'Agente v1' }, headers: agent.create_new_auth_token, as: :json
      post "#{base_path}/publish", headers: agent.create_new_auth_token, as: :json

      put "#{base_path}/draft", params: { name: 'Agente v2 em edicao' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['name']).to eq('Agente v2 em edicao')
      expect(ScanSolo::AiAgentConfig.published_for(account).name).to eq('Agente v1')
    end

    it 'persists and round-trips every RF-20 field' do
      payload = {
        name: 'Agente Comercial',
        enabled: true,
        model_provider: 'openai',
        model_selection: 'gpt-4.1',
        role: 'SDR virtual',
        objective: 'Qualificar leads',
        persona: 'Consultivo',
        tone: 'Profissional',
        instructions: 'Responda em pt-BR',
        service_rules: 'Nunca prometa desconto',
        qualification_playbook: %w[orcamento prazo],
        required_qualification_fields: %w[orcamento],
        restricted_information: %w[preco_interno],
        forbidden_subjects: %w[concorrentes],
        transfer_criteria: 'Cliente pede humano',
        response_limits: 'Ate 3 mensagens por turno',
        service_hours: '09:00-20:00 America/Sao_Paulo'
      }

      put "#{base_path}/draft", params: payload, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['name']).to eq('Agente Comercial')
      expect(body['qualification_playbook']).to eq(%w[orcamento prazo])
      expect(body['service_hours']).to eq('09:00-20:00 America/Sao_Paulo')
    end
  end

  describe 'POST .../ai_agent_config/publish' do
    it 'atomically swaps the active published version' do
      put "#{base_path}/draft", params: { name: 'Agente v1' }, headers: agent.create_new_auth_token, as: :json
      post "#{base_path}/publish", headers: agent.create_new_auth_token, as: :json
      first_published_id = response.parsed_body['id']

      put "#{base_path}/draft", params: { name: 'Agente v2' }, headers: agent.create_new_auth_token, as: :json
      post "#{base_path}/publish", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['id']).not_to eq(first_published_id)
      expect(response.parsed_body['name']).to eq('Agente v2')
    end
  end

  describe 'account without ScanSolo enabled' do
    let(:disabled_account) { create(:account, scansolo_enabled: false) }
    let(:disabled_agent) { create(:user, account: disabled_account, role: :agent) }

    it 'returns 404' do
      get "/api/v1/accounts/#{disabled_account.id}/scan_solo/ai_agent_config", headers: disabled_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'production configuration contract' do
    it 'exposes the allowed models and default safety configuration' do
      get base_path, headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['available_models']).to eq(%w[gpt-4.1-mini gpt-4.1 gpt-5.1 gpt-5.2])
      expect(response.parsed_body['draft']).to include('allowed_inbox_ids' => [], 'opt_out_keywords' => %w[PARAR SAIR STOP])
    end

    it 'rejects foreign inboxes, invalid model names and malformed arrays before persistence' do
      foreign_inbox = create(:inbox)
      [
        { allowed_inbox_ids: [foreign_inbox.id] }, { model_selection: 'foo' },
        { allowed_inbox_ids: ['1'] }, { allowed_inbox_ids: '1' },
        { opt_out_keywords: 'STOP' }, { opt_out_keywords: [1] }
      ].each do |payload|
        put "#{base_path}/draft", params: payload, headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
      expect(ScanSolo::AiAgentConfig.draft_for!(account).allowed_inbox_ids).to eq([])
    end

    it 'round-trips and publishes the new fields' do
      inbox = create(:inbox, account: account)
      payload = { allowed_inbox_ids: [inbox.id], opt_out_keywords: ['BASTA'] }
      put "#{base_path}/draft", params: payload, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include(payload.stringify_keys)
      post "#{base_path}/publish", headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body).to include(payload.stringify_keys)
    end

    it 'allows agent reads but rejects draft and publish writes' do
      reader = create(:user, account: account, role: :agent)
      headers = reader.create_new_auth_token
      get base_path, headers: headers, as: :json
      expect(response).to have_http_status(:success)
      put "#{base_path}/draft", params: { name: 'Unauthorized' }, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      post "#{base_path}/publish", headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
