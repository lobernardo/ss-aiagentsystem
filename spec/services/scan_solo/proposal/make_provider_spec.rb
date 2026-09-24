require 'rails_helper'

RSpec.describe ScanSolo::Proposal::MakeProvider do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account, custom_attributes: { 'budget' => '5000', 'internal' => 'private' }) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end
  let(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
  let(:correlation_id) { SecureRandom.uuid }
  let(:version) { proposal.versions.create!(generate_correlation_id: correlation_id) }

  before do
    ScanSolo::AiAgentConfig.draft_for!(account).update!(required_qualification_fields: ['budget'])
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  it 'delegates generation to the existing transport with correlation and qualification data' do
    freeze_time do
      expect(ScanSolo::Make::OutboundRequestService).to receive(:call).with(
        account: account, action: 'proposal.generate', correlation_id: correlation_id, idempotency_key: correlation_id, retry_count: 0,
        payload: {
          account_id: account.id, opportunity_id: opportunity.id, proposal_version_id: version.id, qualification: { 'budget' => '5000' },
          requested_by_user_id: user.id, requested_at: Time.current.iso8601
        }
      )

      described_class.request_generation(proposal_version: version, correlation_id: correlation_id, actor: user)
    end
  end

  it 'sends a null requested_by_user_id for AI-initiated requests' do
    expect(ScanSolo::Make::OutboundRequestService).to receive(:call)
      .with(hash_including(payload: hash_including(requested_by_user_id: nil)))

    described_class.request_generation(proposal_version: version, correlation_id: correlation_id)
  end

  it 'delegates sends without inventing a commercial value or artifact' do
    expect(ScanSolo::Make::OutboundRequestService).to receive(:call).with(
      hash_including(action: 'proposal.send', correlation_id: correlation_id, idempotency_key: correlation_id)
    )

    described_class.request_send(proposal_version: version, correlation_id: correlation_id, conversation: conversation)
    expect(version.reload.value).to be_nil
    expect(version.artifact_url).to be_nil
  end

  describe 'RF-37: HTTP transport through WebMock' do
    let(:scenario_url) { 'https://hook.make.example/scenario-webhook' }

    before do
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :scenario_url).and_return(scenario_url)
      allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :secret).and_return('make-outbound-secret')
    end

    it 'persists a MakeRequest carrying the version correlation id and posts the CT-05 payload' do
      stub_request(:post, scenario_url).to_return(status: 200, body: '{}')

      request = described_class.request_generation(proposal_version: version, correlation_id: correlation_id, actor: user)

      expect(request).to be_sent
      expect(request.correlation_id).to eq(version.generate_correlation_id)
      expect(
        a_request(:post, scenario_url).with do |req|
          body = JSON.parse(req.body)
          body['action'] == 'proposal.generate' && body['proposal_version_id'] == version.id &&
            body['qualification'] == { 'budget' => '5000' } && body['requested_by_user_id'] == user.id && body['requested_at'].present?
        end
      ).to have_been_made.once
      expect(version.reload).to be_generating
    end

    {
      'timeout' => ->(stub) { stub.to_timeout },
      'network_error' => ->(stub) { stub.to_raise(SocketError) },
      'provider_unavailable' => ->(stub) { stub.to_return(status: 503, body: 'down') }
    }.each do |reason, configure|
      it "marks the version failed with #{reason} without raising" do
        configure.call(stub_request(:post, scenario_url))

        expect do
          described_class.request_generation(proposal_version: version, correlation_id: correlation_id)
        end.not_to raise_error

        expect(version.reload).to be_failed
        expect(version.failure_reason).to eq(reason)
        expect(ScanSolo::MakeRequest.find_by(correlation_id: correlation_id)).to be_failed
      end
    end
  end
end
