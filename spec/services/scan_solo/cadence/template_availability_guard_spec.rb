# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Cadence::TemplateAvailabilityGuard do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
  end
  let(:cadence_definition) { ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2]) }
  let(:enrollment) { ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: cadence_definition) }
  let(:attempt) { enrollment.attempts.first }

  before do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente', enabled: true)
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  describe 'automation disabled' do
    before do
      draft = ScanSolo::AiAgentConfig.draft_for!(account)
      draft.update!(enabled: false)
      ScanSolo::AiAgent::PublishService.new(account: account).call
    end

    it 'blocks with automation_disabled' do
      result = described_class.check(enrollment: enrollment, attempt: attempt)

      expect(result).to be_blocked
      expect(result.reason).to eq('automation_disabled')
    end
  end

  describe 'a fake/non-WhatsApp inbox (RF-71)' do
    it 'treats the fake template reference as available' do
      result = described_class.check(enrollment: enrollment, attempt: attempt)

      expect(result).not_to be_blocked
    end
  end

  describe 'a WhatsApp inbox with a missing/unapproved template' do
    before { stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook') }

    let(:whatsapp_channel) { create(:channel_whatsapp, sync_templates: false) }
    let(:whatsapp_inbox) { whatsapp_channel.inbox }
    let(:contact_inbox) { create(:contact_inbox, inbox: whatsapp_inbox, source_id: '123456789') }
    let(:conversation) { create(:conversation, contact_inbox: contact_inbox, inbox: whatsapp_inbox, account: account) }

    it 'blocks with template_unavailable' do
      result = described_class.check(enrollment: enrollment, attempt: attempt)

      expect(result).to be_blocked
      expect(result.reason).to eq('template_unavailable')
    end
  end

  describe 'integration with the due-attempt job (RF-67)' do
    before do
      draft = ScanSolo::AiAgentConfig.draft_for!(account)
      draft.update!(enabled: false)
      ScanSolo::AiAgent::PublishService.new(account: account).call
    end

    it 'produces a recorded skip result and zero send attempts when automation is disabled' do
      expect do
        ScanSolo::CadenceDueAttemptJob.process_attempt!(attempt, enforce_window: false)
      end.not_to change { Message.where(conversation_id: conversation.id).count }

      expect(attempt.reload).to be_skipped
    end
  end
end
