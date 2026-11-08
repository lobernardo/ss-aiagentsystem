# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ScanSolo manual "proposta enviada" API (CT-03, CT-04)', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:stage) { :qualificado }
  let(:opportunity) { ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: stage) }
  let(:quote_status) { :awaiting_reply }
  let!(:quote_request) do
    ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid, status: quote_status)
  end
  let!(:post_proposal_definition) { ScanSolo::CadenceDefinition.create!(stage: 'proposta_enviada', version: 1, offsets: [24, 72, 168]) }
  let(:audits) { ScanSolo::AuditEvent.where(event_type: 'quote_request.handled_manually') }

  describe 'POST /pipeline_opportunities/:id/quote_request/handled_manually (CT-03)' do
    let(:path) { "/api/v1/accounts/#{account.id}/scan_solo/pipeline_opportunities/#{opportunity.id}/quote_request/handled_manually" }

    { 'agent' => :agent, 'administrator' => :admin }.each do |role, user_name|
      it "accepts an #{role} and returns the opportunity as proposta_enviada_manual" do
        user = public_send(user_name)
        post path, headers: user.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to include('id' => opportunity.id, 'stage' => 'proposta_enviada',
                                                'quote_request_status' => 'handled_manually',
                                                'commercial_status' => 'proposta_enviada_manual')
        expect(quote_request.reload).to have_attributes(status: 'handled_manually', handled_manually_by: user)
        expect(audits.sole.payload).to include('mode' => 'single')
        expect(ScanSolo::CadenceEnrollment.where(opportunity: opportunity, cadence_definition: post_proposal_definition).sole).to be_active
      end
    end

    shared_examples 'a 422 without changes' do |code|
      it "returns 422 #{code} and changes no row" do
        expect { post path, headers: agent.create_new_auth_token, as: :json }
          .to not_change(ScanSolo::PipelineStageEvent, :count)
          .and(not_change(ScanSolo::AuditEvent, :count))
          .and(not_change(ScanSolo::CadenceEnrollment, :count))
          .and(not_change { ScanSolo::QuoteRequest.where(opportunity_id: opportunity.id).map(&:attributes) })
          .and(not_change { opportunity.reload.stage })

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq('error' => code)
      end
    end

    context 'without a quote request' do
      before { quote_request.destroy! }

      it_behaves_like 'a 422 without changes', 'quote_request_missing'
    end

    %i[replied handled_manually].each do |status|
      context "with a #{status} request" do
        let(:quote_status) { status }

        it_behaves_like 'a 422 without changes', 'quote_request_closed'
      end
    end

    context 'with a stage other than qualificado or proposta_enviada' do
      let(:stage) { :em_qualificacao }

      it_behaves_like 'a 422 without changes', 'invalid_stage'
    end

    it 'returns 404 for an opportunity of another account' do
      other_account = create(:account, scansolo_enabled: true)
      other_contact = create(:contact, account: other_account)
      other = ScanSolo::PipelineOpportunity.create!(account: other_account, contact: other_contact, stage: :qualificado,
                                                    conversation: create(:conversation, account: other_account, contact: other_contact))
      ScanSolo::QuoteRequest.create!(account: other_account, opportunity: other, correlation_id: SecureRandom.uuid, status: :awaiting_reply)

      post "/api/v1/accounts/#{account.id}/scan_solo/pipeline_opportunities/#{other.id}/quote_request/handled_manually",
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(other.reload.stage).to eq('qualificado')
    end

    it 'returns 404 when ScanSolo is disabled for the account' do
      account.update!(scansolo_enabled: false)

      post path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(quote_request.reload).to be_awaiting_reply
    end

    it 'returns 401 without a token' do
      post path, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(quote_request.reload).to be_awaiting_reply
    end
  end

  describe 'POST /quote_requests/handled_manually (CT-04)' do
    let(:path) { "/api/v1/accounts/#{account.id}/scan_solo/quote_requests/handled_manually" }

    it 'returns one result per id and changes only the eligible one' do
      handled_contact = create(:contact, account: account)
      handled_opportunity = ScanSolo::PipelineOpportunity.create!(account: account, contact: handled_contact, stage: :proposta_enviada,
                                                                  conversation: create(:conversation, account: account, contact: handled_contact))
      handled_request = ScanSolo::QuoteRequest.create!(account: account, opportunity: handled_opportunity, correlation_id: SecureRandom.uuid,
                                                       status: :handled_manually)
      other_account = create(:account, scansolo_enabled: true)
      other_contact = create(:contact, account: other_account)
      foreign_opportunity = ScanSolo::PipelineOpportunity.create!(account: other_account, contact: other_contact, stage: :qualificado,
                                                                  conversation: create(:conversation, account: other_account, contact: other_contact))
      ids = [opportunity.id, handled_opportunity.id, foreign_opportunity.id]

      expect do
        post path, params: { opportunity_ids: ids }, headers: agent.create_new_auth_token, as: :json
      end.to(not_change { handled_request.reload.attributes }.and(not_change { foreign_opportunity.reload.attributes }))

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('results' => [
                                           { 'opportunity_id' => opportunity.id, 'result' => 'handled' },
                                           { 'opportunity_id' => handled_opportunity.id, 'result' => 'quote_request_closed' },
                                           { 'opportunity_id' => foreign_opportunity.id, 'result' => 'not_found' }
                                         ])
      expect([opportunity.reload.stage, quote_request.reload.status, quote_request.handled_manually_by])
        .to eq(['proposta_enviada', 'handled_manually', agent])
      expect(audits.sole).to have_attributes(subject: opportunity, payload: include('mode' => 'bulk', 'cadence_skipped' => 'legacy_bulk'))
      expect(ScanSolo::CadenceEnrollment.joins(:cadence_definition)
                                        .where(opportunity_id: [opportunity.id, handled_opportunity.id], status: %i[active paused],
                                               cadence_definition: { stage: 'proposta_enviada' })).to be_none
    end

    it 'accepts an administrator' do
      post path, params: { opportunity_ids: [opportunity.id] }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['results']).to eq([{ 'opportunity_id' => opportunity.id, 'result' => 'handled' }])
    end

    [[], nil, ['x']].each do |ids|
      it "returns 422 invalid_opportunity_ids for #{ids.inspect}" do
        body = ids.nil? ? {} : { opportunity_ids: ids }

        expect { post path, params: body, headers: agent.create_new_auth_token, as: :json }.not_to(change { quote_request.reload.attributes })

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq('error' => 'invalid_opportunity_ids')
      end
    end

    it 'returns 404 when ScanSolo is disabled for the account' do
      account.update!(scansolo_enabled: false)

      post path, params: { opportunity_ids: [opportunity.id] }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(quote_request.reload).to be_awaiting_reply
    end

    it 'returns 401 without a token' do
      post path, params: { opportunity_ids: [opportunity.id] }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(quote_request.reload).to be_awaiting_reply
    end
  end
end
