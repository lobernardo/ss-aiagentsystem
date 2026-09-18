# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Make::OutboundRequestService do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:scenario_url) { 'https://hook.make.example/scenario-webhook' }
  let(:scenario_secret) { 'make-outbound-secret' }
  let(:correlation_id) { SecureRandom.uuid }
  let(:idempotency_key) { SecureRandom.uuid }
  let(:payload) { { opportunity_id: 42, proposal_version_id: 7 } }

  def call
    described_class.call(account: account, action: 'proposal.generate', payload: payload,
                         correlation_id: correlation_id, idempotency_key: idempotency_key)
  end

  describe 'RF-84: no production Make credential required for the standard configured path' do
    before do
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :scenario_url).and_return(scenario_url)
      allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :secret).and_return(scenario_secret)

      stub_request(:post, scenario_url).to_return(status: 200, body: '{}')
    end

    it 'creates a ScanSolo::MakeRequest evidence row carrying the correlation id and idempotency key' do
      request = call

      expect(request).to be_persisted
      expect(request).to be_sent
      expect(request.correlation_id).to eq(correlation_id)
      expect(request.idempotency_key).to eq(idempotency_key)
      expect(request.action).to eq('proposal.generate')
    end

    it 'attaches the idempotency key header and correlation id to the outbound request' do
      call

      expect(
        a_request(:post, scenario_url)
          .with(headers: { 'X-Idempotency-Key' => idempotency_key })
          .with { |req| JSON.parse(req.body)['correlation_id'] == correlation_id }
      ).to have_been_made.once
    end

    it 'never persists the outbound secret into the stored request payload' do
      request = call

      expect(request.payload.to_s).not_to include(scenario_secret)
    end

    it 'marks the request failed and increments retry_count on a non-success response' do
      stub_request(:post, scenario_url).to_return(status: 500, body: 'boom')

      request = call

      expect(request).to be_failed
      expect(request.retry_count).to eq(1)
    end
  end

  describe 'RF-84: raises loudly instead of silently no-oping when Make is not configured' do
    before do
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :scenario_url).and_return(nil)
    end

    it 'raises NotConfiguredError and creates no request row' do
      expect { call }.to raise_error(ScanSolo::Make::OutboundRequestService::NotConfiguredError)
      expect(ScanSolo::MakeRequest.count).to eq(0)
    end
  end

  describe 'RF-84: no Make HTTP call occurs during a standard AI turn absent a proposal/Make-backed action' do
    it 'issues zero outbound requests to any host for a plain turn fixture' do
      contact = create(:contact, account: account)
      conversation = create(:conversation, account: account, contact: contact)
      message = create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact)

      draft = ScanSolo::AiAgentConfig.draft_for!(account)
      draft.update!(name: 'Agente ScanSolo', enabled: true)
      ScanSolo::AiAgent::PublishService.new(account: account).call

      ScanSolo::AiTurn::TurnOrchestrator.call(message: message, llm_provider: ScanSolo::TestMode::MockLlmProvider, actions: [])

      expect(WebMock).not_to have_requested(:post, /hook\.make/)
    end
  end
end
