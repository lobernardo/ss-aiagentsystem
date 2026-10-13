# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ScanSolo Proposal Template API (CT-05)', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/scan_solo/proposal_template" }
  let(:content_type) { ScanSolo::Proposal::TemplateUploadService::CONTENT_TYPE }
  let(:valid_file) { Rack::Test::UploadedFile.new(StringIO.new(scan_solo_docx_valid), content_type, original_filename: 'proposta-v3.docx') }
  let!(:previous) do
    ScanSolo::Proposal::TemplateUploadService.call(
      account: account, actor: admin,
      file: Rack::Test::UploadedFile.new(StringIO.new(scan_solo_docx_valid), content_type, original_filename: 'proposta-v2.docx')
    )
  end

  def upload(bytes, user: admin, filename: 'proposta.docx')
    post path, params: { file: Rack::Test::UploadedFile.new(StringIO.new(bytes), content_type, original_filename: filename) },
               headers: user.create_new_auth_token
  end

  describe 'POST (RF-17)' do
    it 'activates a valid template and keeps the previous one inactive' do
      post path, params: { file: valid_file }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      template = ScanSolo::ProposalTemplate.active_for(account)
      expect(response.parsed_body['template']).to include('id' => template.id, 'filename' => 'proposta-v3.docx')
      expect(previous.reload).to have_attributes(active: false)
      event = ScanSolo::AuditEvent.where(event_type: 'proposal_template.uploaded').order(:id).last
      expect(event.payload).to include('template_id' => template.id, 'previous_template_id' => previous.id)
    end

    {
      'split_placeholders' => [-> { scan_solo_docx_valid(split: ['VALOR_EXTENSO']) }, ['VALOR_EXTENSO']],
      'invalid_docx' => [-> { file_fixture('sample.pdf').binread }, nil]
    }.each do |code, (bytes, placeholders)|
      it "rejects #{code} with 422 and keeps the active template" do
        expect { upload(instance_exec(&bytes)) }.not_to(change { [ScanSolo::ProposalTemplate.count, ActiveStorage::Blob.count] })

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq(code)
        expect(response.parsed_body['placeholders']).to eq(placeholders) if placeholders
        expect(ScanSolo::ProposalTemplate.active_for(account).id).to eq(previous.id)
      end
    end

    it 'names the missing placeholder' do
      body = (ScanSolo::Proposal::TemplateDocument::PLACEHOLDERS - ['VALOR_EXTENSO']).map { |name| "{{#{name}}}" }

      upload(scan_solo_docx(paragraphs: body))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'missing_placeholders', 'placeholders' => ['VALOR_EXTENSO'])
      expect(ScanSolo::ProposalTemplate.active_for(account).id).to eq(previous.id)
    end

    it 'names an unknown placeholder' do
      body = ScanSolo::Proposal::TemplateDocument::PLACEHOLDERS.map { |name| "{{#{name}}}" } + ['{{XYZ}}']

      upload(scan_solo_docx(paragraphs: body))

      expect(response.parsed_body).to eq('error' => 'unknown_placeholders', 'placeholders' => ['XYZ'])
    end

    it 'rejects a file above 15 MiB before reading it (RNF-06)' do
      expect(ScanSolo::Proposal::TemplateDocument).not_to receive(:new)

      upload('a' * ((15 * 1024 * 1024) + 1))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'file_too_large')
    end

    it 'requires a file' do
      post path, params: {}, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'file_required')
    end

    it 'forbids an agent' do
      expect { upload(scan_solo_docx_valid, user: agent) }.not_to change(ScanSolo::ProposalTemplate, :count)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to eq('error' => 'forbidden')
    end

    it 'returns 404 when ScanSolo is disabled' do
      account.update!(scansolo_enabled: false)

      upload(scan_solo_docx_valid)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET (RF-18)' do
    it 'returns the active template metadata without a blob URL' do
      get path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['template']).to eq(
        'id' => previous.id, 'filename' => 'proposta-v2.docx', 'byte_size' => previous.byte_size, 'sha256' => previous.sha256,
        'uploaded_by' => { 'id' => admin.id, 'name' => admin.name }, 'uploaded_at' => previous.created_at.as_json
      )
      expect(response.body).not_to include('rails/active_storage')
    end

    it 'returns null without an active template' do
      previous.update!(active: false)

      get path, headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body).to eq('template' => nil)
    end
  end

  describe 'account isolation (RF-21)' do
    let(:other_account) { create(:account, scansolo_enabled: true) }
    let(:other_admin) { create(:user, account: other_account, role: :administrator) }

    it 'reads and replaces only the template of the route account' do
      get "/api/v1/accounts/#{other_account.id}/scan_solo/proposal_template", headers: other_admin.create_new_auth_token, as: :json
      expect(response.parsed_body).to eq('template' => nil)

      post "/api/v1/accounts/#{other_account.id}/scan_solo/proposal_template", params: { file: valid_file },
                                                                               headers: other_admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(ScanSolo::ProposalTemplate.active_for(other_account).uploaded_by).to eq(other_admin)
      expect(ScanSolo::ProposalTemplate.active_for(account).id).to eq(previous.id)

      post path, params: { file: valid_file }, headers: other_admin.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
