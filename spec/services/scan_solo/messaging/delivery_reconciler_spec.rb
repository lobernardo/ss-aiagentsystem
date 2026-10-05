# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Messaging::DeliveryReconciler do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:channel) { create(:channel_whatsapp, account: account, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511955554444') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado)
  end

  before { stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook') }

  def template_message(origin:, inbox: self.inbox, conversation: self.conversation)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     additional_attributes: { 'scansolo_origin' => origin })
  end

  describe 'cadence attempts (RF-27)' do
    let(:definition) { ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2, 24]) }
    let(:enrollment) { ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: definition) }
    let(:attempt) { enrollment.attempts.order(:step).first }
    let(:message) { template_message(origin: 'cadence') }

    before { ScanSolo::Cadence::AttemptEvidenceRecorder.record_dispatched!(attempt, message: message) }

    it 'marks the attempt sent with sent_at once the native WhatsApp message gets a source_id' do
      message.update!(source_id: 'wamid.accepted')

      described_class.call(message: message)

      expect(attempt.reload).to be_sent
      expect(attempt.sent_at).to be_present
    end

    it 'keeps the attempt dispatched while the provider has not accepted the message' do
      described_class.call(message: message)

      expect(attempt.reload).to be_dispatched
    end

    it 'marks the attempt failed with the native external error' do
      message.update!(status: :failed, external_error: '131047: Re-engagement message')

      described_class.call(message: message)

      expect(attempt.reload).to have_attributes(result: 'failed', external_error: '131047: Re-engagement message')
    end

    it 'is idempotent: a later update never rewrites a reconciled attempt' do
      message.update!(source_id: 'wamid.accepted')
      described_class.call(message: message)
      message.update!(status: :failed, external_error: 'late failure')

      expect { described_class.call(message: message) }.not_to(change { attempt.reload.attributes })
      expect(attempt).to be_sent
    end

    it 'counts a persisted non-failed message on a non-WhatsApp inbox as accepted' do
      web_inbox = create(:inbox, account: account)
      web_conversation = create(:conversation, account: account, inbox: web_inbox, contact: contact)
      web_attempt = enrollment.attempts.order(:step).second
      web_message = template_message(origin: 'cadence', inbox: web_inbox, conversation: web_conversation)
      ScanSolo::Cadence::AttemptEvidenceRecorder.record_dispatched!(web_attempt, message: web_message)

      described_class.call(message: web_message)

      expect(web_attempt.reload).to be_sent
    end

    it 'is reached through the native message_updated event (CT-09)' do
      message.update!(source_id: 'wamid.accepted')

      ScanSolo::ConversationListener.instance.message_updated(
        Events::Base.new('message_updated', Time.zone.now, { message: message })
      )

      expect(attempt.reload).to be_sent
    end
  end

  describe 'proposal versions (RF-41)' do
    let(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
    let(:message) { template_message(origin: 'proposal') }
    let!(:version) do
      proposal.versions.create!(status: :approved, value: 1000, currency: 'BRL', artifact_url: 'https://x.test/a.pdf', sent_message: message)
    end

    before { ScanSolo::CadenceDefinition.create!(stage: 'proposta_enviada', version: 1, offsets: [24, 72, 168]) }

    it 'marks the version failed with the external error and leaves the stage unchanged on a native failure' do
      message.update!(status: :failed, external_error: 'template rejected by Meta')

      described_class.call(message: message)

      expect(version.reload).to have_attributes(status: 'failed', failure_reason: 'template rejected by Meta')
      expect(opportunity.reload).to be_qualificado
    end

    it 'marks the version sent and moves the opportunity to proposta_enviada once accepted' do
      message.update!(source_id: 'wamid.proposal')

      described_class.call(message: message)

      expect(version.reload).to be_sent
      expect(opportunity.reload).to be_proposta_enviada
    end
  end

  describe 'generated proposal delivered by Chatwoot (RF-30)' do
    let(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity) }
    let(:message) { template_message(origin: 'proposal') }
    let!(:version) do
      proposal.versions.create!(status: :generated, value: 1000, currency: 'BRL', artifact_url: 'https://x.test/a.pdf',
                                generate_callback_applied_at: Time.current, sent_message: message)
    end
    let!(:definition) { ScanSolo::CadenceDefinition.create!(stage: 'proposta_enviada', version: 1, offsets: [24, 72, 168]) }
    let(:stage_events) { ScanSolo::PipelineStageEvent.where(opportunity: opportunity) }

    it 'keeps the version generated and the stage while the message has no source_id' do
      described_class.call(message: message)

      expect(version.reload).to be_generated
      expect(opportunity.reload).to be_qualificado
    end

    it 'marks the version sent, moves the stage and enrolls the active proposta_enviada cadence on acceptance' do
      message.update!(source_id: 'wamid.proposal')

      described_class.call(message: message)

      expect(version.reload).to be_sent
      expect(opportunity.reload).to be_proposta_enviada
      expect(stage_events.count).to eq(1)
      enrollment = opportunity.cadence_enrollments.active.sole
      expect(enrollment.cadence_definition).to eq(definition)
      expect(enrollment.attempts.count).to eq(definition.offsets.size)
    end

    it 'fails a sent version on a later native failure with 1 audit, keeping stage and enrollment' do
      message.update!(source_id: 'wamid.proposal')
      described_class.call(message: message)
      message.update!(status: :failed, external_error: '131049: Meta chose not to deliver')

      expect { 2.times { described_class.call(message: message) } }.not_to change(stage_events, :count)

      expect(version.reload).to have_attributes(status: 'failed', failure_reason: '131049: Meta chose not to deliver')
      expect(ScanSolo::AuditEvent.where(event_type: 'proposal.delivery_failed_after_sent', subject: opportunity).count).to eq(1)
      expect(opportunity.reload).to be_proposta_enviada
      expect(opportunity.cadence_enrollments.active.count).to eq(1)
    end
  end

  describe 'manual lead initial template (RF-08)' do
    let(:message) { template_message(origin: 'manual_lead') }
    let(:audits) { ScanSolo::AuditEvent.where(subject: opportunity, event_type: 'pipeline.manual_lead_template_failed') }

    before { opportunity }

    it 'records one audit with the native external error, even after a later message_updated' do
      message.update!(status: :failed, external_error: '131026: Message undeliverable')
      event = Events::Base.new('message_updated', Time.zone.now, { message: message })

      ScanSolo::ConversationListener.instance.message_updated(event)
      ScanSolo::ConversationListener.instance.message_updated(event)

      expect(audits.count).to eq(1)
      expect(audits.first.payload).to eq('message_id' => message.id, 'external_error' => '131026: Message undeliverable')
    end

    it 'records nothing while the message is accepted' do
      message.update!(source_id: 'wamid.manual')

      described_class.call(message: message)

      expect(audits.count).to eq(0)
    end
  end
end
