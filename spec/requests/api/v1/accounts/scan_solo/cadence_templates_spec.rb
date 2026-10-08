# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ScanSolo Cadence Templates API', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/scan_solo/cadence_templates" }
  let(:last_sync) { Time.zone.parse('2026-09-20 12:00:00') }
  let(:channel) do
    create(:channel_whatsapp, account: account, sync_templates: false, message_templates_last_updated: last_sync, message_templates: [
             { 'name' => 'scansolo_cadence_novo_lead_v1_step1', 'status' => 'APPROVED', 'language' => 'pt_BR',
               'components' => [{ 'type' => 'BODY', 'text' => 'Oi!' }] },
             { 'name' => 'scansolo_followup_2', 'status' => 'REJECTED', 'language' => 'pt_BR',
               'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}' }] }
           ])
  end

  before do
    stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
    ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2, 24])
    ScanSolo::CadenceDefinition.create!(stage: 'em_contato', version: 1, offsets: [24])
    ScanSolo::AiAgentConfig.draft_for!(account).update!(name: 'Agente', enabled: true, allowed_inbox_ids: [channel.inbox.id])
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  describe 'GET /cadence_templates' do
    before do
      ScanSolo::TemplateMapping.create!(account: account, stage: 'novo_lead', step: 2, template_name: 'scansolo_followup_2',
                                        language: 'pt_BR', params: [{ 'source' => 'contact_first_name' }])
    end

    it 'returns one row per active stage/step plus the CT-09 slot rows with availability and Meta status' do
      get path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      rows = response.parsed_body.index_by { |row| [row['stage'], row['step']] }
      # CT-09 (RNF-11): the manual-lead and follow-up slots join the proposal send row; CT-07 adds the email notice slot.
      expect(rows.keys).to contain_exactly(
        ['novo_lead', 1], ['novo_lead', 2], ['em_contato', 1],
        ['proposta_enviada', nil], ['lead_manual_inicial', nil], ['proposta_acompanhamento', nil], ['proposta_aviso_email', nil]
      )

      expect(rows[['novo_lead', 1]]).to include(
        'template_name' => 'scansolo_cadence_novo_lead_v1_step1', 'language' => 'pt_BR', 'mapped' => false,
        'availability' => 'available', 'block_reason' => nil, 'meta_status' => 'APPROVED'
      )
      expect(Time.zone.parse(rows[['novo_lead', 1]]['last_synced_at'])).to eq(last_sync)
      expect(rows[['novo_lead', 2]]).to include(
        'template_name' => 'scansolo_followup_2', 'mapped' => true, 'params' => [{ 'source' => 'contact_first_name' }],
        'availability' => 'blocked', 'block_reason' => 'template_rejected', 'meta_status' => 'REJECTED'
      )
      expect(rows[['em_contato', 1]]).to include('availability' => 'blocked', 'block_reason' => 'template_missing', 'meta_status' => nil)
      expect(rows[['proposta_enviada', nil]]).to include(
        'template_name' => 'scansolo_proposal_send', 'availability' => 'blocked', 'block_reason' => 'template_missing'
      )
    end

    it 'lists the slot rows last, in CT-09 order, with their naming conventions' do
      get path, headers: agent.create_new_auth_token, as: :json

      slots = response.parsed_body.last(4)
      expect(slots.pluck('stage', 'step', 'template_name', 'mapped')).to eq(
        [
          ['proposta_enviada', nil, 'scansolo_proposal_send', false],
          ['lead_manual_inicial', nil, 'scansolo_lead_manual_inicial', false],
          ['proposta_acompanhamento', nil, 'scansolo_proposta_acompanhamento', false],
          ['proposta_aviso_email', nil, 'scansolo_proposta_aviso_email', false]
        ]
      )
    end
  end

  describe 'PUT /cadence_templates' do
    let(:payload) do
      { stage: 'novo_lead', step: 1, template_name: 'scansolo_boas_vindas', language: 'pt_BR',
        params: [{ source: 'contact_first_name' }, { source: 'static', value: 'ScanSolo' }] }
    end

    it 'lets an administrator upsert the mapping and returns the re-evaluated row' do
      expect do
        put path, params: payload, headers: admin.create_new_auth_token, as: :json
      end.to change(ScanSolo::AuditEvent.where(event_type: 'template_mapping.updated'), :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        'stage' => 'novo_lead', 'step' => 1, 'template_name' => 'scansolo_boas_vindas', 'mapped' => true,
        'availability' => 'blocked', 'block_reason' => 'template_missing'
      )
      mapping = ScanSolo::TemplateMapping.find_by!(account: account, stage: 'novo_lead', step: 1)
      expect(mapping.params).to eq([{ 'source' => 'contact_first_name' }, { 'source' => 'static', 'value' => 'ScanSolo' }])

      put path, params: payload.merge(template_name: 'scansolo_boas_vindas_v2'), headers: admin.create_new_auth_token, as: :json
      expect(ScanSolo::TemplateMapping.where(account: account, stage: 'novo_lead', step: 1).pluck(:template_name)).to eq(['scansolo_boas_vindas_v2'])
    end

    it 'maps the proposal send with step null' do
      put path, params: payload.merge(stage: 'proposta_enviada', step: nil, params: []), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['step']).to be_nil
      expect(ScanSolo::TemplateMapping.find_by!(account: account, stage: 'proposta_enviada', step: nil).template_name).to eq('scansolo_boas_vindas')
    end

    it 'maps the post-proposal follow-up slot with step null' do
      put path, params: payload.merge(stage: 'proposta_acompanhamento', step: nil, template_name: 'scansolo_acompanhamento'),
                headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('stage' => 'proposta_acompanhamento', 'step' => nil, 'template_name' => 'scansolo_acompanhamento',
                                              'mapped' => true)
    end

    it 'maps the CT-07 email notice slot with step null' do
      put path, params: payload.merge(stage: 'proposta_aviso_email', step: nil, template_name: 'scansolo_aviso_email'),
                headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('stage' => 'proposta_aviso_email', 'step' => nil, 'template_name' => 'scansolo_aviso_email',
                                              'mapped' => true)
    end

    it 'rejects a step on a single-template slot and a null step on a cadence stage with 422' do
      put path, params: payload.merge(stage: 'lead_manual_inicial', step: 1), headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      put path, params: payload.merge(step: nil), headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      expect(ScanSolo::TemplateMapping.count).to eq(0)
    end

    it 'rejects a non-allowlisted parameter source with 422' do
      put path, params: payload.merge(params: [{ source: 'phone_number' }]), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('invalid_template_mapping')
      expect(ScanSolo::TemplateMapping.count).to eq(0)
    end

    it 'rejects an unknown step with 422' do
      put path, params: payload.merge(step: 3), headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'forbids an agent with 403' do
      put path, params: payload, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(ScanSolo::TemplateMapping.count).to eq(0)
    end
  end
end
