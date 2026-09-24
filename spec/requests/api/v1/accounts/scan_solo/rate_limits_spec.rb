# frozen_string_literal: true

require 'rails_helper'

# RF-49 / RNF-06: per-account throttles on ScanSolo administrative writes.
RSpec.describe 'ScanSolo per-account rate limits', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/scan_solo" }
  # 127.0.0.1 is safelisted by config/initializers/rack_attack.rb.
  let(:headers) { admin.create_new_auth_token.merge('REMOTE_ADDR' => '203.0.113.10') }
  let!(:source) do
    ScanSolo::KnowledgeSource.create!(account: account, added_by: admin, source_type: :faq, title: 'FAQ', content: 'Texto', origin: 'manual')
  end

  around do |example|
    original_enabled = Rack::Attack.enabled
    Rack::Attack.enabled = true
    Rack::Attack.reset!
    example.run
    Rack::Attack.reset!
    Rack::Attack.enabled = original_enabled
  end

  before do
    allow(ScanSolo::Knowledge::EmbeddingService).to receive(:call) do |content:, **|
      ScanSolo::TestMode::MockEmbeddingProvider.call(content: content)
    end
  end

  def publish
    post "#{base}/ai_agent_config/publish", headers: headers, as: :json
  end

  def retrieval_test
    post "#{base}/knowledge/retrieval_tests", params: { query: 'garantia' }, headers: headers, as: :json
  end

  def knowledge_write(index)
    case index % 3
    when 0
      post "#{base}/knowledge/sources", params: { source_type: 'faq', title: 'N', content: 'C', origin: 'manual' }, headers: headers, as: :json
    when 1 then patch "#{base}/knowledge/sources/#{source.id}", params: { title: "T#{index}" }, headers: headers, as: :json
    else post "#{base}/knowledge/sources/#{source.id}/reindex", headers: headers, as: :json
    end
  end

  it 'registers the three ScanSolo throttles' do
    expect(Rack::Attack.throttles.keys).to include('scan_solo/knowledge_writes', 'scan_solo/retrieval_tests', 'scan_solo/publish')
  end

  it 'answers 429 on the 11th publish within a minute' do
    10.times do
      publish
      expect(response).to have_http_status(:success)
    end

    publish
    expect(response).to have_http_status(:too_many_requests)
  end

  it 'answers 429 on the 31st retrieval test within a minute' do
    30.times { retrieval_test }
    expect(response).to have_http_status(:success)

    retrieval_test
    expect(response).to have_http_status(:too_many_requests)
  end

  it 'counts knowledge create, update and reindex together and answers 429 on the 21st write' do
    20.times do |index|
      knowledge_write(index)
      expect(response).to have_http_status(:success)
    end

    knowledge_write(20)
    expect(response).to have_http_status(:too_many_requests)
  end

  it 'does not count reads toward the knowledge write limit' do
    25.times { get "#{base}/knowledge/sources", headers: headers, as: :json }

    expect(response).to have_http_status(:success)
    knowledge_write(1)
    expect(response).to have_http_status(:success)
  end

  it 'keeps the limit per account' do
    other_account = create(:account, scansolo_enabled: true)
    other_admin = create(:user, account: other_account, role: :administrator)
    10.times { publish }

    post "/api/v1/accounts/#{other_account.id}/scan_solo/ai_agent_config/publish",
         headers: other_admin.create_new_auth_token.merge('REMOTE_ADDR' => '203.0.113.10'), as: :json
    expect(response).to have_http_status(:success)
  end

  it 'lets an ENV override change the limit' do
    with_modified_env RATE_LIMIT_SCANSOLO_PUBLISH: '2' do
      2.times { publish }
      expect(response).to have_http_status(:success)

      publish
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  it 'falls back to the default when the ENV value is empty' do
    with_modified_env RATE_LIMIT_SCANSOLO_PUBLISH: '' do
      publish
      expect(response).to have_http_status(:success)
    end
  end
end
