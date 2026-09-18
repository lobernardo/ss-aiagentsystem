# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Proposal::ApproveService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
  end
  let(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
  let(:agent) { create(:user, account: account) }
  let(:correlation_id) { SecureRandom.uuid }

  describe 'RF-77: version-integrity guard' do
    it 'rejects approval of a non-current (stale) version' do
      stale_version = proposal.versions.create!(status: :generated)
      proposal.versions.create!(status: :generated) # becomes current, marking stale_version non-current

      expect do
        described_class.call(proposal_version: stale_version.reload, correlation_id: correlation_id, actor: agent)
      end.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe 'RF-78: recording approval' do
    it 'records approved_at/approved_by and moves status to approved' do
      version = proposal.versions.create!(status: :generated)

      result = described_class.call(proposal_version: version, correlation_id: correlation_id, actor: agent)

      expect(result.approved_at).to be_present
      expect(result.approved_by).to eq(agent)
      expect(result).to be_approved
    end

    it 'is idempotent: approving twice does not change the recorded approved_at' do
      version = proposal.versions.create!(status: :generated)

      first = described_class.call(proposal_version: version, correlation_id: correlation_id, actor: agent)
      second = described_class.call(proposal_version: version.reload, correlation_id: SecureRandom.uuid, actor: agent)

      expect(second.approved_at).to eq(first.approved_at)
    end
  end
end
