# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ScanSolo Reports API', type: :request do
  # Monday 2026-11-09 10:00 in São Paulo: the week of 2026-11-02 is closed.
  let(:now) { Time.utc(2026, 11, 9, 13, 0, 0) }
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:fixture_content) { 'Meu WhatsApp é +5511988887777 e o e-mail lead.sigiloso@empresa.com.br' }
  let(:reports_path) { "/api/v1/accounts/#{account.id}/scan_solo/reports" }

  around do |example|
    travel_to(now) { example.run }
  end

  # A stalled lead whose contact holds PII and whose conversation holds one
  # message: none of it may reach the report body (RNF-01).
  def create_stalled_opportunity
    contact = create(:contact, account: account, name: "Lead #{SecureRandom.hex(3)}",
                               email: "#{SecureRandom.hex(4)}@empresa.com.br",
                               phone_number: format('+55119%08d', SecureRandom.random_number(100_000_000)))
    conversation = create(:conversation, account: account, contact: contact)
    create(:message, account: account, conversation: conversation, message_type: :incoming, content: fixture_content)
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_contato,
                                          last_customer_interaction_at: now - 3.days, created_at: now - 10.days)
  end

  def scan_solo_row_counts
    connection = ActiveRecord::Base.connection
    connection.tables.grep(/\Ascan_solo_/).sort.index_with { |table| connection.select_value("SELECT COUNT(*) FROM #{table}") }
  end

  def report_query_count
    count = 0
    callback = ->(*, payload) { count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      get reports_path, params: { period: 'week' }, headers: agent.create_new_auth_token, as: :json
    end
    expect(response).to have_http_status(:ok)
    count
  end

  describe 'permissions (RF-11)' do
    it 'returns 404 for an account without ScanSolo enabled' do
      disabled_account = create(:account, scansolo_enabled: false)
      disabled_agent = create(:user, account: disabled_account, role: :agent)

      get "/api/v1/accounts/#{disabled_account.id}/scan_solo/reports",
          params: { period: 'week' }, headers: disabled_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 401 without a token' do
      get reports_path, params: { period: 'week' }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 200 for an administrator' do
      get reports_path, params: { period: 'week' }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['period']).to eq('week')
    end

    it 'returns 200 for an agent' do
      get reports_path, params: { period: 'month' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['period']).to eq('month')
    end
  end

  describe 'request validation (RF-12)' do
    it 'rejects an unknown period with invalid_period' do
      get reports_path, params: { period: 'day' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'invalid_period')
    end

    it 'rejects a missing period with invalid_period' do
      get reports_path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'invalid_period')
    end

    it 'rejects an impossible date with invalid_anchor' do
      get reports_path, params: { period: 'week', anchor: '2026-02-30' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'invalid_anchor')
    end

    it 'rejects an anchor outside YYYY-MM-DD with invalid_anchor' do
      get reports_path, params: { period: 'week', anchor: '2026-11-4' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'invalid_anchor')
    end

    context 'without anchor' do
      # Sunday 2026-11-08 23:00 in São Paulo, already Monday 2026-11-09 in UTC.
      let(:now) { Time.utc(2026, 11, 9, 2, 0, 0) }

      it 'uses the current date in America/Sao_Paulo' do
        get reports_path, params: { period: 'week' }, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['anchor']).to eq('2026-11-08')
        expect(body['starts_at']).to eq('2026-11-02T00:00:00-03:00')
        expect(body['ends_at']).to eq('2026-11-09T00:00:00-03:00')
      end
    end
  end

  describe 'snapshot or live source (RF-14)' do
    let!(:snapshot) do
      ScanSolo::ReportSnapshot.create!(account: account, week_start: Date.new(2026, 11, 2), generated_at: now - 4.hours,
                                       payload: { 'period' => 'week', 'anchor' => '2026-11-02', 'source' => 'snapshot',
                                                  'starts_at' => '2026-11-02T00:00:00-03:00', 'summary' => { 'new_leads' => { 'total' => 7 } } })
    end

    it 'serves the stored payload for a closed week with a snapshot' do
      get reports_path, params: { period: 'week', anchor: '2026-11-05' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['source']).to eq('snapshot')
      expect(response.parsed_body).to eq(snapshot.payload)
    end

    it 'computes the current week live' do
      get reports_path, params: { period: 'week', anchor: '2026-11-09' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['source']).to eq('live')
      expect(response.parsed_body['starts_at']).to eq('2026-11-09T00:00:00-03:00')
    end

    it 'computes a month live even when it contains a snapshotted week' do
      get reports_path, params: { period: 'month', anchor: '2026-11-02' }, headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['source']).to eq('live')
    end

    it 'computes a closed week without snapshot live and stores nothing' do
      expect do
        get reports_path, params: { period: 'week', anchor: '2026-10-28' }, headers: agent.create_new_auth_token, as: :json
      end.not_to change(ScanSolo::ReportSnapshot, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['source']).to eq('live')
      expect(response.parsed_body['starts_at']).to eq('2026-10-26T00:00:00-03:00')
    end
  end

  describe 'read-only (RF-11)' do
    it 'leaves the row count of every scan_solo_* table unchanged' do
      create_stalled_opportunity
      headers = agent.create_new_auth_token
      before = scan_solo_row_counts

      get reports_path, params: { period: 'week', anchor: '2026-10-28' }, headers: headers, as: :json
      get reports_path, params: { period: 'month' }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(scan_solo_row_counts).to eq(before)
    end
  end

  describe 'query count (RNF-02)' do
    it 'issues the same number of queries with 3 and with 30 stalled opportunities' do
      3.times { create_stalled_opportunity }
      report_query_count
      with_three = report_query_count
      expect(response.parsed_body['stalled'].size).to eq(3)

      27.times { create_stalled_opportunity }
      with_thirty = report_query_count
      expect(response.parsed_body['stalled'].size).to eq(30)

      expect(with_thirty).to eq(with_three)
    end
  end

  describe 'privacy (RNF-01)' do
    it 'never exposes e-mail, phone or message content' do
      create_stalled_opportunity

      get reports_path, params: { period: 'week' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['stalled'].size).to eq(1)
      expect(response.body).not_to include('@')
      expect(response.body).not_to include('+55')
      expect(response.body).not_to include(fixture_content)
    end
  end
end
