require 'rails_helper'

RSpec.describe ScanSolo::Proposal::MakeProvider do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, custom_attributes: { 'budget' => '5000', 'internal' => 'private' }) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end
  let(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
  let(:version) { proposal.versions.create! }
  let(:correlation_id) { SecureRandom.uuid }

  before do
    ScanSolo::AiAgentConfig.draft_for!(account).update!(required_qualification_fields: ['budget'])
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  it 'delegates generation to the existing transport with correlation and qualification data' do
    expect(ScanSolo::Make::OutboundRequestService).to receive(:call).with(
      account: account, action: 'proposal.generate', correlation_id: correlation_id, idempotency_key: correlation_id,
      payload: { account_id: account.id, opportunity_id: opportunity.id, proposal_version_id: version.id, qualification: { 'budget' => '5000' } }
    )

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
end
