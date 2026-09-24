# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ScanSolo Contact Opt-Out API', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let(:path) { "/api/v1/accounts/#{account.id}/scan_solo/contacts/#{contact.id}/opt_out" }

  before { ScanSolo::OptOut::MarkService.call(contact: contact, source: 'keyword') }

  describe 'GET .../contacts/:contact_id/opt_out' do
    it 'shows the marker to any account user' do
      get path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('contact_id' => contact.id, 'opted_out' => true)
    end
  end

  describe 'DELETE .../contacts/:contact_id/opt_out' do
    it 'lets an administrator clear the marker with one audit event' do
      expect do
        delete path, headers: admin.create_new_auth_token, as: :json
      end.to change(ScanSolo::AuditEvent.where(event_type: 'contact.opt_out_cleared', subject: contact), :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('contact_id' => contact.id, 'opted_out' => false)
      expect(ScanSolo::ContactExtension.opted_out?(contact)).to be false
    end

    it 'forbids an agent and leaves the marker unchanged' do
      delete path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(ScanSolo::ContactExtension.opted_out?(contact)).to be true
      expect(ScanSolo::AuditEvent.where(event_type: 'contact.opt_out_cleared')).to be_empty
    end

    it 'returns 404 for a contact of another account' do
      other_contact = create(:contact, account: create(:account, scansolo_enabled: true))

      delete "/api/v1/accounts/#{account.id}/scan_solo/contacts/#{other_contact.id}/opt_out", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
