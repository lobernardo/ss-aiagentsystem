# frozen_string_literal: true

require 'rails_helper'

# RF-04 replaces the OC/RF-78 expectations: approval is always required, audited and triggers the e-mail delivery once.
RSpec.describe ScanSolo::Proposal::ApproveService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end
  let(:quote_request) do
    ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid, status: :replied,
                                   commercial: { 'total_value' => '12500.00' })
  end
  let(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
  let(:agent) { create(:user, account: account) }
  let(:version) { proposal.versions.create!(status: :awaiting_approval, quote_request: quote_request, value: 12_500, currency: 'BRL') }
  let(:approved_audits) { ScanSolo::AuditEvent.where(event_type: 'proposal.approved') }

  def approve(target = version)
    described_class.call(proposal_version: target, actor: agent)
  end

  it 'approves an awaiting_approval version, audits it and enqueues one delivery (RF-04)' do
    result = approve

    expect(result.reload).to have_attributes(status: 'approved', approved_at: be_present, approved_by: agent)
    expect(approved_audits.sole).to have_attributes(subject: opportunity, actor: agent, correlation_id: quote_request.correlation_id)
    expect(approved_audits.sole.payload).to include('proposal_version_id' => version.id)
    expect(ScanSolo::ProposalDeliveryJob).to have_been_enqueued.with(version.id).exactly(:once)
  end

  it 'is idempotent: a 2nd approval records no audit and enqueues no delivery (RF-04, RNF-02)' do
    approve
    approved_at = version.reload.approved_at

    expect { approve(ScanSolo::ProposalVersion.find(version.id)) }.not_to change(ScanSolo::AuditEvent, :count)

    expect(version.reload.approved_at).to eq(approved_at)
    expect(ScanSolo::ProposalDeliveryJob).to have_been_enqueued.exactly(:once)
  end

  it 'returns a sent version untouched (RF-04)' do
    version.update!(status: :sent)

    expect(approve.reload).to be_sent
    expect(approved_audits).to be_none
    expect(ScanSolo::ProposalDeliveryJob).not_to have_been_enqueued
  end

  it 'records one audit and one delivery for two concurrent approvals (RF-04, RNF-02)' do
    version

    Array.new(2) { Thread.new { approve(ScanSolo::ProposalVersion.find(version.id)) } }.each(&:join)

    expect(approved_audits.count).to eq(1)
    expect(ScanSolo::ProposalDeliveryJob).to have_been_enqueued.exactly(:once)
  end

  it 'ignores a published require_proposal_approval = false (RF-04)' do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente', enabled: true, allowed_inbox_ids: [conversation.inbox_id], require_proposal_approval: false)
    ScanSolo::AiAgent::PublishService.new(account: account).call

    expect(version.reload).to be_awaiting_approval
    expect(ScanSolo::ProposalDeliveryJob).not_to have_been_enqueued

    approve

    expect(version.reload).to be_approved
    expect(approved_audits.count).to eq(1)
    expect(ScanSolo::ProposalDeliveryJob).to have_been_enqueued.exactly(:once)
  end

  it 'rejects a non-current version with not_current_version (RF-04, CT-02)' do
    stale = version
    stale.update!(status: :rejected)
    proposal.versions.create!(status: :rejected, quote_request: quote_request)
    stale.update!(status: :awaiting_approval)

    expect { approve(stale.reload) }
      .to raise_error(CustomExceptions::ScanSolo::ProposalActionRejected) { |e| expect(e.code).to eq('not_current_version') }
    expect(approved_audits).to be_none
  end

  it 'rejects a version that is not awaiting approval with not_awaiting_approval (RF-04, CT-02)' do
    version.update!(status: :generating)

    expect { approve }.to raise_error(CustomExceptions::ScanSolo::ProposalActionRejected) { |e| expect(e.code).to eq('not_awaiting_approval') }
    expect(version.reload).to have_attributes(status: 'generating', approved_at: nil)
    expect(ScanSolo::ProposalDeliveryJob).not_to have_been_enqueued
  end
end
