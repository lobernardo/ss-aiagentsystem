# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'ScanSolo Make callback webhook (CT-06)', type: :request do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbound_secret) { 'make-inbound-secret' }
  let(:correlation_id) { SecureRandom.uuid }
  let(:idempotency_key) { SecureRandom.uuid }

  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end
  let(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
  let(:version) { proposal.versions.create!(generate_correlation_id: correlation_id) }

  let(:make_request) do
    ScanSolo::MakeRequest.create!(
      account: account, correlation_id: correlation_id, idempotency_key: idempotency_key,
      action: 'proposal.generate', payload: { opportunity_id: opportunity.id, proposal_version_id: version.id }, status: :sent
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
        artifact_url: 'https://make.example/proposals/7.pdf',
        total_value: 4321.5,
        currency: 'BRL',
        valid_until: '2026-11-04T00:00:00Z'
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
      expect(version.reload).to have_attributes(status: 'generating', value: nil)
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
      expect(ScanSolo::AuditEvent.where(event_type: 'make.callback_rejected', subject: callback).count).to eq(1)
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
      expect(ScanSolo::AuditEvent.where(event_type: 'make.callback_rejected').sole.payload).to include('rejection_reason' => 'schema_invalid')
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

    it 'RF-38: applies the generate result to the ProposalVersion with the callback value' do
      make_request

      post_callback(success_payload.to_json)

      expect(response).to have_http_status(:ok)
      expect(version.reload).to have_attributes(
        status: 'awaiting_approval', value: BigDecimal('4321.5'), currency: 'BRL', artifact_url: 'https://make.example/proposals/7.pdf'
      )
    end

    # RF-01 replaces OC/RF-29: the callback schedules the approval request, never the delivery.
    it 'RF-01/RF-26/RF-33: persists valid_until, schedules the approval request and leaves the stage untouched' do
      make_request

      expect { post_callback(success_payload.to_json) }.to have_enqueued_job(ScanSolo::ProposalApprovalRequestJob).with(version.id)

      expect(ScanSolo::ProposalDeliveryJob).not_to have_been_enqueued

      expect(version.reload.valid_until).to eq(Time.zone.parse('2026-11-04T00:00:00Z'))
      expect(opportunity.reload).to be_qualificado
      expect(opportunity.cadence_enrollments).to be_none
      expect(ScanSolo::AuditEvent.where(event_type: 'proposal.generated', subject: opportunity).count).to eq(1)
    end

    it 'RF-26: schedules no approval request for a rejected callback' do
      make_request

      expect { post_callback(success_payload.to_json, signature: 'bad') }.not_to have_enqueued_job(ScanSolo::ProposalApprovalRequestJob)

      expect(version.reload).to be_generating
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
      expect(version.reload).to have_attributes(status: 'failed', failure_reason: 'provider_unavailable')
    end
  end

  describe 'RF-19: total_value checked against the quote request (CT-08)' do
    let(:quote_request) do
      ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid, status: :replied,
                                     commercial: { 'total_value' => '12500.00' })
    end
    let(:version) { proposal.versions.create!(generate_correlation_id: correlation_id, quote_request: quote_request) }
    let(:rejections) { ScanSolo::AuditEvent.where(event_type: 'make.callback_rejected') }

    before { make_request }

    def callback_with(**result)
      success_payload.merge(result: success_payload[:result].merge(result)).to_json
    end

    it 'rejects a divergent total_value with 422 and writes nothing to the version' do
      post_callback(callback_with(total_value: 12_000.00))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(version.reload).to have_attributes(status: 'generating', value: nil, artifact_url: nil)
      expect(make_request.reload).to be_sent
      expect(ScanSolo::MakeCallback.sole).to have_attributes(applied: false, rejection_reason: 'total_value_mismatch')
      expect(rejections.sole).to have_attributes(correlation_id: quote_request.correlation_id, subject: ScanSolo::MakeCallback.sole)
      expect(rejections.sole.payload).to include('rejection_reason' => 'total_value_mismatch', 'expected_total_value' => '12500.00',
                                                 'total_value' => 12_000.0)
    end

    it 'applies an equal total_value in another notation' do
      post_callback(callback_with(total_value: 12_500.0))

      expect(response).to have_http_status(:ok)
      expect(version.reload).to have_attributes(status: 'awaiting_approval', value: BigDecimal(12_500))
      expect(rejections.count).to eq(0)
    end

    it 'accepts and stores the optional artifact_sha256 and template_version (RF-25)' do
      post_callback(callback_with(total_value: 12_500, artifact_sha256: 'ab' * 32, template_version: 'proposta-v3'))

      expect(response).to have_http_status(:ok)
      expect(version.reload).to have_attributes(status: 'awaiting_approval', artifact_sha256: 'ab' * 32)
      expect(ScanSolo::AuditEvent.where(event_type: 'proposal.generated').sole.payload).to include('template_version' => 'proposta-v3')
    end

    it 'rejects a malformed artifact_sha256 as schema_invalid and audits it (RF-20)' do
      post_callback(callback_with(total_value: 12_500, artifact_sha256: 'not-a-sha'))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(version.reload).to be_generating
      expect(rejections.sole).to have_attributes(correlation_id: quote_request.correlation_id)
      expect(rejections.sole.payload).to include('rejection_reason' => 'schema_invalid')
    end

    it 'writes no audit nor callback for an invalid signature (RF-20)' do
      post_callback(callback_with(total_value: 12_000), signature: 'bad')

      expect(response).to have_http_status(:unauthorized)
      expect(ScanSolo::AuditEvent.count).to eq(0)
      expect(ScanSolo::MakeCallback.count).to eq(0)
    end
  end

  describe 'RF-39: a rejected callback does not block a later valid one' do
    it 'applies a valid callback after a schema-invalid one with the same correlation id' do
      make_request

      post_callback({ correlation_id: correlation_id, action: 'proposal.generate' }.to_json)
      expect(response).to have_http_status(:unprocessable_entity)

      post_callback(success_payload.to_json)

      expect(response).to have_http_status(:ok)
      expect(ScanSolo::MakeCallback.where(correlation_id: correlation_id).pluck(:applied)).to contain_exactly(false, true)
      expect(version.reload).to be_awaiting_approval
    end
  end

  describe 'RF-38: send callback' do
    let(:send_correlation_id) { SecureRandom.uuid }
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:version) do
      proposal.versions.create!(status: :approved, value: 1000, currency: 'BRL', artifact_url: 'https://make.example/a.pdf',
                                generate_correlation_id: correlation_id, send_correlation_id: send_correlation_id)
    end
    let(:send_payload) do
      {
        correlation_id: send_correlation_id, idempotency_key: send_correlation_id, action: 'proposal.send', status: 'success',
        result: { proposal_version_id: version.id, sent_at: Time.current.iso8601, transport_message_id: 'make-1' }
      }
    end

    before do
      ScanSolo::CadenceDefinition.create!(stage: 'proposta_enviada', version: 1, offsets: [24, 72, 168])
      ScanSolo::MakeRequest.create!(
        account: account, correlation_id: send_correlation_id, idempotency_key: send_correlation_id, action: 'proposal.send',
        payload: { proposal_version_id: version.id, requested_by_user_id: admin.id }, status: :sent
      )
    end

    it 'creates exactly one native template message and moves the stage once delivery is accepted' do
      # scansolo-operacao-centralizada RF-31 (RNF-11): the accepted proposal is followed by 1 follow-up template.
      follow_ups = conversation.messages.where("additional_attributes ->> 'scansolo_origin' = 'proposal_follow_up'")
      expect do
        perform_enqueued_jobs(only: EventDispatcherJob) { post_callback(send_payload.to_json) }
      end.to change(conversation.messages.outgoing, :count).by(2).and change(follow_ups, :count).by(1)

      expect(response).to have_http_status(:ok)
      message = version.reload.sent_message
      expect(message.additional_attributes).to include('scansolo_origin' => 'proposal')
      expect(message.additional_attributes['template_params']).to include('name' => 'scansolo_proposal_send')
      expect(version).to be_sent
      expect(opportunity.reload).to be_proposta_enviada
      expect(ScanSolo::MakeRequest.find_by(correlation_id: send_correlation_id)).to be_completed
    end

    it 'does not send a second message on redelivery' do
      post_callback(send_payload.to_json)

      expect { post_callback(send_payload.to_json) }.not_to change(Message, :count)
      expect(response).to have_http_status(:ok)
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
      expect(version.reload.value).to eq(BigDecimal('4321.5'))
    end

    it 'changes nothing on a duplicate delivery' do
      make_request
      post_callback(success_payload.to_json)
      applied_at = version.reload.generate_callback_applied_at

      expect { post_callback(success_payload.to_json) }.not_to(change { version.reload.attributes })
      expect(response).to have_http_status(:ok)
      expect(version.generate_callback_applied_at).to eq(applied_at)
    end
  end
end
