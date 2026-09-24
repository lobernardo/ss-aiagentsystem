# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ScanSolo Status API', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:path) { "/api/v1/accounts/#{account.id}/scan_solo/status" }

  before do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'sk-secret-openai-key')
    ScanSolo::AiAgentConfig.draft_for!(account).update!(name: 'Agente', enabled: true, model_selection: 'gpt-4.1-mini',
                                                        allowed_inbox_ids: [inbox.id])
    ScanSolo::AiAgent::PublishService.new(account: account).call
    allow(Sidekiq::Cron::Job).to receive(:find).and_return(nil)
  end

  it 'returns the CT-07 status to an administrator with no secret value' do
    get path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.keys).to contain_exactly(
      'git_sha', 'pending_migrations', 'cadence_definitions', 'llm_key_configured', 'agent', 'inbox_conflicts',
      'cadence_cron_registered', 'proposal_integration', 'templates_last_synced_at'
    )
    expect(body).to include('llm_key_configured' => true, 'cadence_cron_registered' => false, 'inbox_conflicts' => [],
                            'templates_last_synced_at' => {})
    expect(body['agent']).to eq('published' => true, 'enabled' => true, 'model' => 'gpt-4.1-mini', 'allowed_inbox_ids' => [inbox.id])
    expect(body['cadence_definitions'].keys).to contain_exactly('novo_lead', 'em_contato', 'em_qualificacao', 'proposta_enviada')
    expect(body['proposal_integration']).to be_in(%w[configured blocked])

    secrets = ['sk-secret-openai-key'] + Array(Rails.application.credentials.dig(:scan_solo, :make)&.values).compact.map(&:to_s)
    secrets.each { |secret| expect(response.body).not_to include(secret) }
  end

  it 'forbids an agent' do
    get path, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:forbidden)
  end
end
