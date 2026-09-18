require 'rails_helper'

# The api/v1/accounts/:account_id/scan_solo namespace is registered in
# config/routes.rb, but Api::V1::Accounts::ScanSolo::BaseController has no
# concrete subclass yet (later ScanSolo feature controllers will inherit it
# and register their own resources under that namespace). To exercise its
# gating behaviour over a real HTTP request, we draw a temporary route for the
# duration of each example and restore the application's real routes afterwards.
RSpec.describe 'Api::V1::Accounts::ScanSolo::BaseController', type: :request do
  before do
    test_controller_class = Class.new(Api::V1::Accounts::ScanSolo::BaseController) do
      def index
        render json: { ok: true }
      end
    end

    Rails.application.routes.draw do
      get '/scan_solo_base_controller_spec/:account_id', to: test_controller_class.action(:index)
    end
  end

  after do
    Rails.application.reload_routes!
  end

  let(:account) { create(:account) }

  context 'when the account does not have ScanSolo enabled' do
    it 'returns 404 for an unauthenticated request' do
      get "/scan_solo_base_controller_spec/#{account.id}", as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 even for an authenticated user' do
      user = create(:user, account: account)

      get "/scan_solo_base_controller_spec/#{account.id}",
          headers: user.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when the account has ScanSolo enabled' do
    before { account.update!(scansolo_enabled: true) }

    it 'passes through to native authentication and rejects unauthenticated requests' do
      get "/scan_solo_base_controller_spec/#{account.id}", as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'allows an authenticated account user through' do
      user = create(:user, account: account)

      get "/scan_solo_base_controller_spec/#{account.id}",
          headers: user.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['ok']).to be(true)
    end
  end
end
