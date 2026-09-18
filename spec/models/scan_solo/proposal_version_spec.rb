# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::ProposalVersion do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
  end
  let(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }

  describe 'version numbering' do
    it 'auto-assigns sequential version numbers per proposal' do
      v1 = proposal.versions.create!
      v2 = proposal.versions.create!

      expect(v1.version_number).to eq(1)
      expect(v2.version_number).to eq(2)
    end
  end

  describe 'current-version integrity (RF-77)' do
    it 'marks the previous version non-current when a new one is generated' do
      v1 = proposal.versions.create!
      expect(v1.reload).to be_is_current

      v2 = proposal.versions.create!

      expect(v1.reload.is_current).to be false
      expect(v2.reload.is_current).to be true
    end

    it 'mirrors the current version onto Proposal#current_version_id' do
      v1 = proposal.versions.create!
      expect(proposal.reload.current_version_id).to eq(v1.id)

      v2 = proposal.versions.create!
      expect(proposal.reload.current_version_id).to eq(v2.id)
    end

    it 'enforces at most one current version per proposal at the database level' do
      proposal.versions.create!
      v2 = proposal.versions.create!

      expect do
        ActiveRecord::Base.transaction(requires_new: true) do
          # rubocop:disable Rails/SkipsModelValidations -- deliberately bypassing the app-level
          # callback to prove the DB-level partial unique index is the real backstop (RF-77).
          described_class.insert!(
            { proposal_id: proposal.id, version_number: 99, is_current: true, status: 0, created_at: Time.current, updated_at: Time.current },
            returning: false
          )
          # rubocop:enable Rails/SkipsModelValidations
        end
      end.to raise_error(ActiveRecord::RecordNotUnique)

      expect(v2.reload).to be_is_current
    end
  end

  describe '#approval_required?' do
    it 'defaults to true when there is no published agent config' do
      version = proposal.versions.create!

      expect(version.approval_required?).to be true
    end

    it 'reflects the published agent config value' do
      draft = ScanSolo::AiAgentConfig.draft_for!(account)
      draft.update!(name: 'Agente', enabled: true, require_proposal_approval: false)
      ScanSolo::AiAgent::PublishService.new(account: account).call

      version = proposal.versions.create!

      expect(version.approval_required?).to be false
    end
  end
end
