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

  describe 'status vocabulary (CT-01)' do
    it 'keeps codes 0-4 and adds awaiting_approval and rejected' do
      expect(described_class.statuses).to eq(
        'generating' => 0, 'generated' => 1, 'approved' => 2, 'sent' => 3, 'failed' => 4, 'awaiting_approval' => 5, 'rejected' => 6
      )
    end

    it 'lists the statuses that hold a quote request open (RF-07)' do
      expect(described_class::NON_TERMINAL_STATUSES).to eq(%w[generating awaiting_approval approved])
    end
  end

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

  describe '#proposal_number (RF-26)' do
    it 'assigns a distinct SS-YYYY-NNNNNN number to each version on creation' do
      v1 = proposal.versions.create!
      v2 = proposal.versions.create!

      expect(v1.reload.proposal_number).to match(/\ASS-#{v1.created_at.year}-\d{6}\z/)
      expect(v2.reload.proposal_number).to match(/\ASS-#{v2.created_at.year}-\d{6}\z/)
      expect(v1.proposal_number).not_to eq(v2.proposal_number)
      expect(v1.proposal_number).to eq(format('SS-%<year>d-%<id>06d', year: v1.created_at.year, id: v1.id))
    end
  end

  describe '#document_url (RF-29)' do
    it 'is the Chatwoot-served blob URL once the PDF is attached' do
      version = proposal.versions.create!
      version.update_column(:artifact_url, 'https://make.example.com/proposal.pdf') # rubocop:disable Rails/SkipsModelValidations
      version.document.attach(io: Rails.root.join('spec/fixtures/files/sample.pdf').open, filename: 'proposta.pdf',
                              content_type: 'application/pdf')

      expect(version.document_url).to start_with(ENV.fetch('FRONTEND_URL'))
      expect(version.document_url).not_to eq(version.artifact_url)
    end

    it 'is nil without a document' do
      expect(proposal.versions.create!.document_url).to be_nil
    end
  end

  describe '#quote_request' do
    it 'links every version generated from the same quote request (RF-06)' do
      quote_request = ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid)
      rejected = proposal.versions.create!(quote_request: quote_request, status: :rejected)
      version = proposal.versions.create!(quote_request: quote_request)

      expect(quote_request.reload.proposal_versions).to contain_exactly(rejected, version)
    end
  end

  describe 'approval and notice associations' do
    it 'links the rejecting user, the approval request message and the WhatsApp notice' do
      user = create(:user, account: account)
      approval_request = create(:message, account: account, conversation: conversation)
      notice = create(:message, account: account, conversation: conversation)
      version = proposal.versions.create!(status: :rejected, rejected_by: user, rejected_at: Time.current,
                                          approval_request_message: approval_request, notice_message: notice)

      reloaded = described_class.find(version.id)

      expect(reloaded.rejected_by).to eq(user)
      expect(reloaded.approval_request_message).to eq(approval_request)
      expect(reloaded.notice_message).to eq(notice)
    end
  end
end
