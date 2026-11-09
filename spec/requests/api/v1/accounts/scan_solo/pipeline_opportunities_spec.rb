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

  describe 'PATCH .../pipeline_opportunities/:id (lead e-mail, CT-09)' do
    let(:admin) { create(:user, account: account, role: :administrator) }

    it 'writes the lead e-mail on the contact and exposes it in show and index (RF-09, CT-01)' do
      patch base_path, params: { email: 'lead@empresa.com.br' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['lead_email']).to eq('lead@empresa.com.br')
      expect(contact.reload.email).to eq('lead@empresa.com.br')

      get "/api/v1/accounts/#{account.id}/scan_solo/pipeline_opportunities", headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body.find { |item| item['id'] == opportunity.id }['lead_email']).to eq('lead@empresa.com.br')
    end

    it 'refuses a malformed or empty e-mail with invalid_email at the boundary' do
      ['x@', ''].each do |email|
        patch base_path, params: { email: email }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq('error' => 'invalid_email')
      end
      expect(contact.reload.email).to be_nil
    end

    it 'refuses an e-mail of another contact with contact_conflict and keeps the contact unchanged' do
      create(:contact, account: account, email: 'lead@empresa.com.br')

      patch base_path, params: { email: 'LEAD@empresa.com.br' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'contact_conflict')
      expect(contact.reload.email).to be_nil
    end

    it 'unblocks the approval refused with lead_email_missing (RF-08)' do
      ScanSolo::AiAgentConfig.draft_for!(account).update!(name: 'Agente', enabled: true)
      ScanSolo::AiAgent::PublishService.new(account: account).call
      quote_request = ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid,
                                                     status: :replied)
      proposal = ScanSolo::Proposal.create!(opportunity: opportunity)
      version = proposal.versions.create!(status: :awaiting_approval, quote_request: quote_request, value: 1000, currency: 'BRL')
      approve = lambda do
        post "/api/v1/accounts/#{account.id}/scan_solo/proposals/#{proposal.id}/approve",
             params: { proposal_version_id: version.id, correlation_id: SecureRandom.uuid }, headers: admin.create_new_auth_token, as: :json
      end

      approve.call
      expect(response.parsed_body).to eq('error' => 'lead_email_missing')

      patch base_path, params: { email: 'lead@empresa.com.br' }, headers: admin.create_new_auth_token, as: :json
      approve.call

      expect(response).to have_http_status(:success)
      expect(version.reload).to be_approved
    end

    it 'exposes the rejection reason of the current version in show (UI-02)' do
      proposal = ScanSolo::Proposal.create!(opportunity: opportunity)
      proposal.versions.create!(status: :rejected, rejection_reason: 'Valor acima do combinado', value: 1000, currency: 'BRL')

      get base_path, headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['proposal']).to include('status' => 'rejected', 'rejection_reason' => 'Valor acima do combinado')
      expect(response.parsed_body['lead_email']).to be_nil
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

  describe 'commercial_status and commercial_forwarded_at (CT-02)' do
    let(:index_path) { "/api/v1/accounts/#{account.id}/scan_solo/pipeline_opportunities" }
    let(:sent_at) { Time.zone.parse('2026-11-05T13:00:00Z') }
    let!(:quote_request) do
      ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid,
                                     status: :replied, sent_at: sent_at)
    end
    let!(:current_version) do
      proposal = ScanSolo::Proposal.create!(opportunity: opportunity)
      proposal.versions.create!(status: :awaiting_approval, quote_request: quote_request).tap { |version| proposal.update!(current_version: version) }
    end
    let!(:unforwarded) do
      other_contact = create(:contact, account: account)
      ScanSolo::PipelineOpportunity.create!(account: account, contact: other_contact, stage: :qualificado,
                                            conversation: create(:conversation, account: account, contact: other_contact))
    end

    it 'exposes the classifier value and the request sent_at in show' do
      get base_path, headers: agent.create_new_auth_token, as: :json

      body = response.parsed_body
      expect(body['commercial_status'])
        .to eq(ScanSolo::Reports::CommercialStatus.call(quote_request: quote_request, current_version: current_version, escalated: false))
      expect(body['commercial_status']).to eq('proposta_em_aprovacao')
      expect(body['commercial_forwarded_at']).to eq(sent_at.iso8601(3))
      expect(body).to include('quote_request_status' => 'replied', 'proposal_status' => 'awaiting_approval')
    end

    it 'exposes the same values in index, and nao_encaminhado with a null forwarded_at without a request' do
      get index_path, headers: agent.create_new_auth_token, as: :json

      by_id = response.parsed_body.index_by { |item| item['id'] }
      expect(by_id[opportunity.id]).to include('commercial_status' => 'proposta_em_aprovacao', 'commercial_forwarded_at' => sent_at.iso8601(3))
      expect(by_id[unforwarded.id]).to include('commercial_status' => 'nao_encaminhado', 'commercial_forwarded_at' => nil)
    end

    # Escalação comercial RF-17/CT-04.
    it 'exposes escalado_wa for an escalated opportunity, and not once it is perdido' do
      unforwarded.update!(escalated_to_commercial_at: Time.current, escalation_reason: 'pedido_humano')
      path = "#{index_path}/#{unforwarded.id}"

      get path, headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['commercial_status']).to eq('escalado_wa')

      unforwarded.update!(stage: :perdido)
      get path, headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['commercial_status']).to eq('nao_encaminhado')
    end

    it 'keeps the index query count constant as opportunities with request and proposal grow (RNF-02)' do
      headers = agent.create_new_auth_token
      count_queries = lambda do
        queries = 0
        callback = ->(*, payload) { queries += 1 unless payload[:name] == 'SCHEMA' || payload[:cached] }
        ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { get index_path, headers: headers, as: :json }
        queries
      end
      add_forwarded_opportunities = lambda do |count|
        count.times do
          lead = create(:contact, account: account)
          record = ScanSolo::PipelineOpportunity.create!(account: account, contact: lead, stage: :proposta_enviada,
                                                         conversation: create(:conversation, account: account, contact: lead))
          request = ScanSolo::QuoteRequest.create!(account: account, opportunity: record, correlation_id: SecureRandom.uuid,
                                                   status: :replied, sent_at: sent_at)
          proposal = ScanSolo::Proposal.create!(opportunity: record)
          proposal.update!(current_version: proposal.versions.create!(status: :sent, quote_request: request))
        end
      end

      add_forwarded_opportunities.call(1)
      count_queries.call
      with_two = count_queries.call
      add_forwarded_opportunities.call(4)
      with_six = count_queries.call

      expect(response.parsed_body.count { |item| item['commercial_status'] == 'proposta_enviada' }).to eq(5)
      expect(with_six).to eq(with_two)
    end
  end
end
