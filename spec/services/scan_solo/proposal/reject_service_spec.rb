# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Proposal::RejectService do
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
  let(:rejected_audits) { ScanSolo::AuditEvent.where(event_type: 'proposal.rejected') }

  def reject(target = version, reason: '  Valor acima do combinado  ')
    described_class.call(proposal_version: target, actor: agent, reason: reason)
  end

  it 'rejects the version with the reason and reopens the quote request (RF-05)' do
    reject

    expect(version.reload).to have_attributes(status: 'rejected', rejected_at: be_present, rejected_by: agent,
                                              rejection_reason: 'Valor acima do combinado', approved_at: nil)
    expect(quote_request.reload).to be_awaiting_reply
  end

  it 'records one audit with reason and actor and delivers nothing (RF-05, RNF-06)' do
    reject

    audit = rejected_audits.sole
    expect(audit).to have_attributes(subject: opportunity, actor: agent, correlation_id: quote_request.correlation_id)
    expect(audit.payload).to include('proposal_version_id' => version.id, 'reason' => 'Valor acima do combinado')
    expect(ScanSolo::ProposalDeliveryJob).not_to have_been_enqueued
    expect(Message.count).to eq(0)
  end

  it 'refuses an approved version with not_awaiting_approval (RF-05, CT-03)' do
    version.update!(status: :approved, approved_at: Time.current)

    expect { reject }.to raise_error(CustomExceptions::ScanSolo::ProposalActionRejected) { |e| expect(e.code).to eq('not_awaiting_approval') }
    expect(version.reload).to have_attributes(status: 'approved', rejection_reason: nil)
    expect(quote_request.reload).to be_replied
    expect(rejected_audits).to be_none
  end

  it 'refuses a non-current version with not_current_version (CT-03)' do
    stale = version
    stale.update!(status: :rejected)
    proposal.versions.create!(status: :rejected, quote_request: quote_request)
    stale.update!(status: :awaiting_approval)

    expect { reject(stale.reload) }
      .to raise_error(CustomExceptions::ScanSolo::ProposalActionRejected) { |e| expect(e.code).to eq('not_current_version') }
    expect(rejected_audits).to be_none
  end

  it 'records one rejection for two concurrent calls (RNF-02)' do
    version

    outcomes = Array.new(2) do
      Thread.new do
        reject(ScanSolo::ProposalVersion.find(version.id))
      rescue CustomExceptions::ScanSolo::ProposalActionRejected => e
        e
      end
    end.map(&:value)

    expect(rejected_audits.count).to eq(1)
    expect(outcomes.grep(CustomExceptions::ScanSolo::ProposalActionRejected).map(&:code)).to eq(['not_awaiting_approval'])
  end
end
