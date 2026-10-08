# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Proposal::CallbackHandler do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end
  let(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
  let(:agent) { create(:user, account: account) }
  let(:correlation_id) { SecureRandom.uuid }
  let(:version) do
    proposal.versions.create!(status: :approved, value: 1000, currency: 'BRL', artifact_url: 'https://x.test/a.pdf',
                              send_correlation_id: correlation_id)
  end

  before { ScanSolo::CadenceDefinition.create!(stage: 'proposta_enviada', version: 1, offsets: [24, 72, 168]) }

  def apply_send(success: true, failure_reason: nil)
    described_class.apply_send_result!(proposal_version: version, correlation_id: correlation_id, success: success,
                                       conversation: conversation, actor: agent, failure_reason: failure_reason)
  end

  describe '.apply_generate_result!' do
    let(:version) { proposal.versions.create!(generate_correlation_id: correlation_id) }

    def apply_generate(success: true, **extra)
      described_class.apply_generate_result!(
        proposal_version: version, correlation_id: correlation_id, success: success, value: 4321.5, currency: 'BRL',
        artifact_url: 'https://make.example/7.pdf', valid_until: '2026-11-04T00:00:00Z', failure_reason: 'docs_copy_failed', **extra
      )
    end

    # RF-01 replaces OC/RF-29: the callback only awaits the commercial approval; nothing reaches the lead.
    it 'moves the version to awaiting_approval and schedules only the approval request (RF-01)' do
      version
      expect { apply_generate }.to not_change(conversation.messages, :count).and not_change(ScanSolo::PipelineStageEvent, :count)

      expect(ScanSolo::ProposalApprovalRequestJob).to have_been_enqueued.with(version.id).exactly(:once)
      expect(ScanSolo::ProposalDeliveryJob).not_to have_been_enqueued

      expect(version.reload).to have_attributes(status: 'awaiting_approval', value: BigDecimal('4321.5'),
                                                valid_until: Time.zone.parse('2026-11-04T00:00:00Z'))
      expect(opportunity.reload).to be_qualificado
      expect(opportunity.cadence_enrollments).to be_none
    end

    it 'stores artifact_sha256 and audits template_version on proposal.generated (RF-25)' do
      apply_generate(artifact_sha256: 'a' * 64, template_version: 'proposta-v3')

      expect(version.reload.artifact_sha256).to eq('a' * 64)
      expect(ScanSolo::AuditEvent.where(event_type: 'proposal.generated').sole.payload)
        .to include('template_version' => 'proposta-v3', 'generate_correlation_id' => correlation_id)
    end

    it 'keeps the failure path without any job and audits proposal.generation_failed (RF-20, RF-27)' do
      apply_generate(success: false)

      expect(ScanSolo::ProposalApprovalRequestJob).not_to have_been_enqueued
      expect(ScanSolo::ProposalDeliveryJob).not_to have_been_enqueued

      expect(version.reload).to have_attributes(status: 'failed', failure_reason: 'docs_copy_failed')
      expect(ScanSolo::AuditEvent.where(event_type: 'proposal.generation_failed').sole)
        .to have_attributes(subject: opportunity, payload: include('reason' => 'docs_copy_failed', 'generate_correlation_id' => correlation_id))
    end
  end

  describe '.apply_send_result!' do
    it 'creates the native proposal message but does not mark the version sent nor move the stage (RF-41)' do
      expect { apply_send }.to change(conversation.messages.outgoing, :count).by(1)

      version.reload
      expect(version).to be_approved
      expect(version.sent_message.additional_attributes).to include('scansolo_origin' => 'proposal')
      expect(version.sent_message.additional_attributes['template_params']).to include('name' => 'scansolo_proposal_send', 'language' => 'pt_BR')
      expect(opportunity.reload).to be_qualificado
    end

    it 'marks the version sent and moves the stage once the delivery is reconciled from the native events' do
      perform_enqueued_jobs(only: EventDispatcherJob) { apply_send }

      expect(version.reload).to be_sent
      expect(opportunity.reload).to be_proposta_enviada
    end

    it 'applies a repeated callback only once' do
      apply_send

      expect { apply_send }.not_to change(conversation.messages, :count)
    end

    it 'records a provider-side send failure without creating a message' do
      expect { apply_send(success: false, failure_reason: 'mock_send_failed') }.not_to change(Message, :count)

      expect(version.reload).to have_attributes(status: 'failed', failure_reason: 'mock_send_failed')
    end

    context 'with an unavailable WhatsApp proposal template (RF-33)' do
      before { stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook') }

      let(:channel) { create(:channel_whatsapp, account: account, sync_templates: false, message_templates: []) }
      let(:inbox) { channel.inbox }
      let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511944443333') }
      let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }

      it 'sends nothing and fails the version with the block reason' do
        expect { apply_send }.not_to change(Message, :count)

        expect(version.reload).to have_attributes(status: 'failed', failure_reason: 'template_missing')
        expect(opportunity.reload).to be_qualificado
      end
    end
  end
end
