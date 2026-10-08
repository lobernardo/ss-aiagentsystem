# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ScanSolo Pipeline Opportunities API lead_state (CT-01)', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, name: 'Milena (WhatsApp)') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
  end

  let(:base_path) { "/api/v1/accounts/#{account.id}/scan_solo/pipeline_opportunities/#{opportunity.id}" }
  let(:writer) { ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state) }

  describe 'GET .../pipeline_opportunities/:id' do
    it 'adds lead_state with its 6 blocks and keeps the current fields' do
      get base_path, headers: agent.create_new_auth_token, as: :json

      body = response.parsed_body
      expect(response).to have_http_status(:success)
      # CT-02 adds the card fields, the quote_request/proposal/initial_template_failure objects and, in v1.3,
      # quote_request_resend_available (RF-56) (RNF-11); CT-01/RF-09 add lead_email (RNF-10).
      expect(body.keys).to eq(%w[id account_id contact_id contact_name lead_email conversation_id owner_id stage last_customer_interaction_at
                                 next_follow_up_at created_at updated_at stage_history lead_source company service city_uf
                                 ai_control_state quote_request_status proposal_status lead_state quote_request proposal
                                 initial_template_failure quote_request_resend_available])
      expect(body['lead_state'].keys).to eq(%w[intent qualification next_action authorized_actions blocks status history])
      expect(body['lead_state']['blocks'].keys).to eq(%w[identificacao servico local escopo execucao comercial])
      expect(body['lead_state']['blocks'].values.flatten.size).to eq(34)
    end

    it 'projects the fields, status and history of the lead state' do
      ScanSolo::AiAgentConfig.draft_for!(account).update!(required_qualification_fields: ['Área'])
      ScanSolo::AiAgent::PublishService.new(account: account).call
      writer.apply_field!(key: 'area', value: '800 m²', status: 'confirmado', source_message_id: nil)

      get base_path, headers: agent.create_new_auth_token, as: :json

      lead_state = response.parsed_body['lead_state']
      expect(lead_state['blocks']['escopo'].first).to include('key' => 'area', 'value' => '800 m²', 'status' => 'confirmado',
                                                              'classification' => 'obrigatorio')
      expect(lead_state).to include('intent' => nil, 'next_action' => nil, 'authorized_actions' => [],
                                    'qualification' => { 'status' => 'em_andamento', 'completed_at' => nil })
      expect(lead_state['status']).to include('stage' => 'em_qualificacao', 'confirmed_fields' => ['area'], 'missing_fields' => [])
      expect(lead_state['history'].pluck('key')).to eq(%w[nome area])
    end

    it 'returns 404 when the account has scansolo disabled' do
      account.update!(scansolo_enabled: false)

      get base_path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'runs the same number of queries with 1 and 50 history entries (RNF-05)' do
      get base_path, headers: agent.create_new_auth_token, as: :json
      counts = [0, 49].map do |extra_events|
        extra_events.times { |index| writer.apply_field!(key: 'area', value: "#{index} m²", status: 'confirmado', source_message_id: nil) }
        count = 0
        counter = ->(*, payload) { count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) || payload[:cached] }
        ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
          get base_path, headers: agent.create_new_auth_token, as: :json
        end
        count
      end

      expect(opportunity.lead_state.events.count).to eq(50)
      expect(counts.first).to eq(counts.last)
    end
  end

  describe 'PATCH .../pipeline_opportunities/:id' do
    it 'exposes the new owner in lead_state.status without writing to the lead state' do
      expect do
        patch base_path, params: { owner_id: agent.id }, headers: agent.create_new_auth_token, as: :json
      end.not_to(change { opportunity.lead_state.reload.updated_at })

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['lead_state']['status']['owner_id']).to eq(agent.id)
    end
  end

  describe 'POST .../pipeline_opportunities/:id/stage_transitions' do
    it 'includes lead_state in the transition and in its idempotent replay' do
      2.times do
        post "#{base_path}/stage_transitions", params: { target_stage: 'qualificado' }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['lead_state']['status']['stage']).to eq('qualificado')
      end
      expect(opportunity.stage_events.count).to eq(1)
    end
  end

  describe 'GET .../pipeline_opportunities' do
    it 'does not include lead_state' do
      get "/api/v1/accounts/#{account.id}/scan_solo/pipeline_opportunities", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.sole).not_to have_key('lead_state')
    end
  end
end
