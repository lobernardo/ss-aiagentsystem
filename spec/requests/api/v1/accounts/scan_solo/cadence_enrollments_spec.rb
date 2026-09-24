# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ScanSolo Cadence Enrollments API', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
  end
  let!(:cadence_definition) { ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2, 24]) }

  let(:base_path) { "/api/v1/accounts/#{account.id}/scan_solo/cadence_enrollments" }

  describe 'POST .../cadence_enrollments (CT-06, manual enrollment)' do
    it 'requires administrator authorization (RF-68)' do
      post base_path, params: { opportunity_id: opportunity.id, cadence_definition_id: cadence_definition.id },
                       headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(ScanSolo::CadenceEnrollment.where(opportunity: opportunity)).to be_none
    end

    it 'creates the enrollment for an authorized administrator' do
      post base_path, params: { opportunity_id: opportunity.id, cadence_definition_id: cadence_definition.id },
                       headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('active')
      expect(response.parsed_body['current_step']).to eq(0)
    end
  end

  describe 'pause/resume/cancel (CT-06)' do
    let!(:enrollment) do
      ScanSolo::Cadence::LifecycleService.enroll!(opportunity: opportunity, cadence_definition: cadence_definition, authorized: true)
    end

    it 'pausing reflects the persisted state within the same request/response cycle' do
      post "#{base_path}/#{enrollment.id}/pause", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('paused')
      expect(enrollment.reload).to be_paused
    end

    it 'resumes a paused enrollment' do
      ScanSolo::Cadence::LifecycleService.pause!(enrollment)

      post "#{base_path}/#{enrollment.id}/resume", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('active')
      expect(enrollment.reload).to be_active
    end

    it 'cancels an enrollment, permanently stopping all remaining attempts' do
      post "#{base_path}/#{enrollment.id}/cancel", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('cancelled')
      expect(enrollment.reload).to be_cancelled
    end
  end

  describe 'GET .../cadence_enrollments (UI-07 data source)' do
    let!(:enrollment) do
      ScanSolo::Cadence::LifecycleService.enroll!(opportunity: opportunity, cadence_definition: cadence_definition, authorized: true)
    end

    it 'lists active enrollments with current step and next attempt' do
      get base_path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body.length).to eq(1)
      expect(body.first['id']).to eq(enrollment.id)
      expect(body.first['current_step']).to eq(0)
      expect(body.first['next_attempt_at']).to be_present
      expect(body.first['contact_name']).to eq(contact.name)
    end
  end
end
