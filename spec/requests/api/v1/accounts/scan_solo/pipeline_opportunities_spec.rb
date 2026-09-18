# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ScanSolo Pipeline Opportunities API', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
  end

  let(:base_path) { "/api/v1/accounts/#{account.id}/scan_solo/pipeline_opportunities/#{opportunity.id}" }

  describe 'GET .../pipeline_opportunities/:id' do
    it 'returns the opportunity for an authenticated account user' do
      get base_path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['id']).to eq(opportunity.id)
      expect(response.parsed_body['stage']).to eq('novo_lead')
    end

    it 'includes the contact, conversation and chronological stage history' do
      ScanSolo::Pipeline::StageTransitionService.new(opportunity: opportunity, target_stage: :em_contato, actor: agent).call

      get base_path, headers: agent.create_new_auth_token, as: :json

      body = response.parsed_body
      expect(body['contact_id']).to eq(contact.id)
      expect(body['contact_name']).to eq(contact.name)
      expect(body['conversation_id']).to eq(conversation.id)
      expect(body['stage_history'].length).to eq(1)
      expect(body['stage_history'].first).to include('from_stage' => 'novo_lead', 'to_stage' => 'em_contato')
    end
  end

  describe 'PATCH .../pipeline_opportunities/:id (owner reassignment)' do
    it 'persists and exposes the new owner' do
      patch base_path, params: { owner_id: agent.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['owner_id']).to eq(agent.id)
      expect(opportunity.reload.owner_id).to eq(agent.id)
    end
  end

  describe 'POST .../pipeline_opportunities/:id/stage_transitions' do
    it 'only applies the transition after server confirmation (200)' do
      post "#{base_path}/stage_transitions", params: { target_stage: 'em_contato' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['stage']).to eq('em_contato')
      expect(opportunity.reload.stage).to eq('em_contato')
    end

    it 'rejects an invalid transition with a 4xx and leaves the stage unchanged' do
      post "#{base_path}/stage_transitions", params: { target_stage: 'inventado' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(opportunity.reload.stage).to eq('novo_lead')
    end

    it 'is idempotent per (opportunity_id, target_stage, actor) within the short window, creating no duplicate history row' do
      headers = agent.create_new_auth_token

      post "#{base_path}/stage_transitions", params: { target_stage: 'em_contato' }, headers: headers, as: :json
      expect(response).to have_http_status(:success)

      expect do
        post "#{base_path}/stage_transitions", params: { target_stage: 'em_contato' }, headers: headers, as: :json
      end.not_to change(ScanSolo::PipelineStageEvent, :count)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['stage']).to eq('em_contato')
    end
  end
end
