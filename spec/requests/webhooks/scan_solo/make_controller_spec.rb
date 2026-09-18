# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::ScanSolo::MakeController, type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbound_secret) { 'make-inbound-secret' }
  let(:correlation_id) { SecureRandom.uuid }
  let(:idempotency_key) { SecureRandom.uuid }

  let(:make_request) do
    ScanSolo::MakeRequest.create!(
      account: account, correlation_id: correlation_id, idempotency_key: idempotency_key,
      action: 'proposal.generate', payload: { opportunity_id: 1 }, status: :sent
    )
  end

  let(:success_payload) do
    {
      correlation_id: correlation_id,
      idempotency_key: idempotency_key,
      action: 'proposal.generate',
      status: 'success',
      result: {
        proposal_version_id: 7,
        artifact_url: 'https://mock-proposals.scansolo.test/7.pdf',
        total_value: 1500.0,
        currency: 'BRL',
        valid_until: 1.week.from_now.iso8601
      }
    }
  end

  def signature_for(body)
    OpenSSL::HMAC.hexdigest('SHA256', inbound_secret, body)
  end

  def post_callback(payload_body, signature: signature_for(payload_body))
    headers = { 'CONTENT_TYPE' => 'application/json' }
    headers['X-Make-Signature'] = signature if signature
    post '/webhooks/scan_solo/make', params: payload_body, headers: headers
  end

  before do
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig)
      .with(:scan_solo, :make, :inbound_signing_secret).and_return(inbound_secret)
  end

  describe 'RF-85: signature/authenticity verification' do
    it 'rejects a callback with an invalid signature without applying a state change' do
      make_request

      expect do
        post_callback(success_payload.to_json, signature: 'not-the-right-signature')
      end.not_to change(ScanSolo::MakeCallback, :count)

      expect(response).to have_http_status(:unauthorized)
      expect(make_request.reload.status).to eq('sent')
    end

    it 'rejects a callback with a missing signature header' do
      make_request

      post_callback(success_payload.to_json, signature: nil)

      expect(response).to have_http_status(:unauthorized)
      expect(ScanSolo::MakeCallback.count).to eq(0)
    end
  end

  describe 'RF-86: schema validation before persisting any result' do
    it 'rejects a malformed (non-JSON) body and records it as an error without mutating state' do
      body = 'not-json'

      expect do
        post_callback(body)
      end.to change(ScanSolo::MakeCallback, :count).by(1)

      expect(response).to have_http_status(:unprocessable_entity)
      callback = ScanSolo::MakeCallback.last
      expect(callback.correlation_id).to be_nil
      expect(callback.applied).to be false
      expect(callback.rejection_reason).to eq('malformed_json')
    end

    it 'rejects a callback missing required fields, recording it as an error without mutating proposal/pipeline state' do
      make_request
      invalid_body = { correlation_id: correlation_id, action: 'proposal.generate' }.to_json

      post_callback(invalid_body)

      expect(response).to have_http_status(:unprocessable_entity)
      callback = ScanSolo::MakeCallback.find_by(correlation_id: correlation_id)
      expect(callback).to be_present
      expect(callback.applied).to be false
      expect(callback.rejection_reason).to eq('schema_invalid')
      expect(make_request.reload.status).to eq('sent')
    end
  end

  describe 'RF-87: no generic/arbitrary callback command' do
    it 'rejects a callback referencing a correlation id/action it was not issued for' do
      unissued_payload = success_payload.merge(correlation_id: SecureRandom.uuid).to_json

      post_callback(unissued_payload)

      expect(response).to have_http_status(:unprocessable_entity)
      callback = ScanSolo::MakeCallback.find_by(correlation_id: JSON.parse(unissued_payload)['correlation_id'])
      expect(callback.applied).to be false
      expect(callback.rejection_reason).to eq('unmatched_request')
    end

    it 'rejects a callback whose action does not match the action the correlation id was issued for' do
      make_request
      mismatched_payload = success_payload.merge(action: 'proposal.send').to_json

      post_callback(mismatched_payload)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(make_request.reload.status).to eq('sent')
    end
  end

  describe 'accepted callback' do
    it 'applies the result and marks the originating make request completed' do
      make_request
      body = success_payload.to_json

      post_callback(body)

      expect(response).to have_http_status(:ok)
      callback = ScanSolo::MakeCallback.find_by(correlation_id: correlation_id)
      expect(callback.applied).to be true
      expect(callback.signature_valid).to be true
      expect(make_request.reload.status).to eq('completed')
    end

    it 'marks the originating make request failed when the callback reports failure' do
      make_request
      failure_payload = {
        correlation_id: correlation_id,
        idempotency_key: idempotency_key,
        action: 'proposal.generate',
        status: 'failure',
        result: {
          proposal_version_id: 7,
          error_code: 'provider_timeout',
          error_message: 'timed out',
          retryable: true
        }
      }.to_json

      post_callback(failure_payload)

      expect(response).to have_http_status(:ok)
      expect(make_request.reload.status).to eq('failed')
    end
  end

  describe 'RNF-05: rate limiting scoped to this endpoint only' do
    around do |example|
      original_enabled = Rack::Attack.enabled
      Rack::Attack.enabled = true
      Rack::Attack.reset!
      example.run
      Rack::Attack.reset!
      Rack::Attack.enabled = original_enabled
    end

    it 'is present and scoped to webhooks/scan_solo/make' do
      expect(Rack::Attack.throttles).to have_key('webhooks/scan_solo/make')
    end

    it 'throttles requests past the configured limit with a 429' do
      limit = ENV.fetch('RATE_LIMIT_SCANSOLO_MAKE_CALLBACK', '60').to_i
      # 127.0.0.1 is safelisted as a trusted IP (config/initializers/rack_attack.rb),
      # so a non-safelisted remote address is required to actually exercise the throttle.
      remote_addr = { 'REMOTE_ADDR' => '203.0.113.5' }

      (limit + 1).times do
        post '/webhooks/scan_solo/make', params: 'not-json',
                                         headers: { 'CONTENT_TYPE' => 'application/json', 'X-Make-Signature' => 'irrelevant' }.merge(remote_addr)
      end

      expect(response).to have_http_status(:too_many_requests)
    end

    it 'does not throttle AI-turn or manual cadence-enrollment endpoints' do
      throttle_names = Rack::Attack.throttles.keys

      expect(throttle_names).not_to include(a_string_matching(/ai_turn/))
      expect(throttle_names).not_to include(a_string_matching(/cadence_enrollment/))
    end
  end

  describe 'RNF-06: permanent replay protection' do
    it 'does not reapply the side effect on a validly-signed replayed callback' do
      make_request
      body = success_payload.to_json

      post_callback(body)
      expect(response).to have_http_status(:ok)

      expect do
        post_callback(body)
      end.not_to change(ScanSolo::MakeCallback, :count)

      expect(response).to have_http_status(:ok)
      expect(make_request.reload.status).to eq('completed')
    end
  end
end
