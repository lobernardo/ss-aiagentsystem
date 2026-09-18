# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Proposal::SendService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end
  let(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
  let(:agent) { create(:user, account: account) }
  let(:correlation_id) { SecureRandom.uuid }

  before do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente', enabled: true, require_proposal_approval: false)
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  def call(version)
    described_class.call(proposal_version: version, correlation_id: correlation_id, conversation: conversation, actor: agent)
  end

  describe 'RF-73: requires a prior successful generate result' do
    it 'rejects a version still generating' do
      version = proposal.versions.create!(status: :generating)

      expect { call(version) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'rejects a version whose generation failed' do
      version = proposal.versions.create!(status: :failed, failure_reason: 'mock_generation_failed')

      expect { call(version) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'proceeds for a generated version' do
      version = proposal.versions.create!(status: :generated, value: 1000, currency: 'BRL', artifact_url: 'https://x.test/a.pdf')

      expect { call(version) }.not_to raise_error
    end
  end

  describe 'RF-77: version-integrity guard' do
    it 'rejects a send against a stale (non-current) version' do
      stale = proposal.versions.create!(status: :generated, value: 1000, currency: 'BRL')
      proposal.versions.create!(status: :generated, value: 1200, currency: 'BRL')

      expect { call(stale.reload) }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe 'RF-78: approval gate' do
    it 'rejects send without a recorded approval when approval is required' do
      draft = ScanSolo::AiAgentConfig.draft_for!(account)
      draft.update!(require_proposal_approval: true)
      ScanSolo::AiAgent::PublishService.new(account: account).call

      version = proposal.versions.create!(status: :generated, value: 1000, currency: 'BRL', artifact_url: 'https://x.test/a.pdf')

      expect { call(version) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(version.reload).not_to be_sent
    end

    it 'sends directly when approval is not required' do
      version = proposal.versions.create!(status: :generated, value: 1000, currency: 'BRL', artifact_url: 'https://x.test/a.pdf')

      result = call(version)

      expect(result).to be_sent
    end
  end

  describe 'RF-79: no premature success' do
    it 'leaves the version status non-sent on a simulated send failure' do
      version = proposal.versions.create!(status: :generated, value: 1000, currency: 'BRL', artifact_url: 'https://x.test/a.pdf')

      failing_provider = Class.new do
        def self.request_send(proposal_version:, correlation_id:, **)
          ScanSolo::Proposal::CallbackHandler.apply_send_result!(
            proposal_version: proposal_version, correlation_id: correlation_id, success: false, failure_reason: 'mock_send_failed'
          )
        end
      end

      described_class.call(
        proposal_version: version, correlation_id: correlation_id, conversation: conversation, actor: agent, provider: failing_provider
      )

      expect(version.reload).not_to be_sent
      expect(version.status).to eq('failed')
    end
  end

  describe 'RF-80: idempotent callback handling' do
    it 'delivering the same mock callback payload twice results in exactly one persisted state change' do
      version = proposal.versions.create!(
        status: :generated, value: 1000, currency: 'BRL', artifact_url: 'https://x.test/a.pdf', send_correlation_id: correlation_id
      )

      first_updated_at = nil
      expect do
        ScanSolo::Proposal::CallbackHandler.apply_send_result!(
          proposal_version: version, correlation_id: correlation_id, success: true, conversation: conversation, actor: agent
        )
        first_updated_at = version.reload.updated_at
      end.to change { conversation.messages.outgoing.count }.by(1)

      expect do
        ScanSolo::Proposal::CallbackHandler.apply_send_result!(
          proposal_version: version, correlation_id: correlation_id, success: true, conversation: conversation, actor: agent
        )
      end.not_to(change { conversation.messages.outgoing.count })

      expect(version.reload.updated_at).to eq(first_updated_at)
    end
  end

  describe 'RF-17/RF-82: success transitions stage and enrolls post-proposal cadence' do
    it 'moves the opportunity to proposta_enviada and creates an active cadence enrollment' do
      ScanSolo::CadenceDefinition.create!(stage: 'proposta_enviada', version: 1, offsets: [24, 72, 168])
      version = proposal.versions.create!(status: :generated, value: 1000, currency: 'BRL', artifact_url: 'https://x.test/a.pdf')

      call(version)

      expect(opportunity.reload).to be_proposta_enviada
      expect(opportunity.cadence_enrollments.active.count).to eq(1)
    end
  end
end
