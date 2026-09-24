# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Cadence::TemplateAvailabilityGuard do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:template) do
    ScanSolo::Messaging::TemplateResolver::Template.new(
      name: 'scansolo_cadence_novo_lead_v1_step1', language: 'pt_BR', params: [{ 'source' => 'contact_first_name' }], mapped: true
    )
  end
  let(:last_sync) { Time.zone.parse('2026-09-20 12:00:00') }

  def synced(status: 'APPROVED', language: 'pt_BR', name: 'scansolo_cadence_novo_lead_v1_step1', body: 'Olá {{1}}, tudo bem?')
    { 'name' => name, 'status' => status, 'language' => language, 'category' => 'UTILITY',
      'components' => [{ 'type' => 'BODY', 'text' => body }, { 'type' => 'FOOTER', 'text' => 'ScanSolo {{9}}' }] }
  end

  describe 'a non-WhatsApp inbox' do
    it 'is available without a Meta catalogue' do
      result = described_class.check(inbox: create(:inbox, account: account), template: template)

      expect(result).not_to be_blocked
    end
  end

  describe 'a WhatsApp inbox' do
    before { stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook') }

    let(:message_templates) { [synced] }
    let(:channel) do
      create(:channel_whatsapp, account: account, sync_templates: false, message_templates: message_templates,
                                message_templates_last_updated: last_sync)
    end

    it 'is available with an approved template in the mapped language and matching BODY placeholders' do
      result = described_class.check(inbox: channel.inbox, template: template)

      expect(result).not_to be_blocked
      expect(result.meta_status).to eq('APPROVED')
      expect(result.last_synced_at).to eq(last_sync)
    end

    {
      'template_missing' => [{ name: 'another_template' }, nil],
      'template_rejected' => [{ status: 'REJECTED' }, 'REJECTED'],
      'template_paused' => [{ status: 'PAUSED' }, 'PAUSED'],
      'template_pending' => [{ status: 'PENDING' }, 'PENDING'],
      'template_disabled' => [{ status: 'DISABLED' }, 'DISABLED'],
      'language_unavailable' => [{ language: 'en_US' }, nil],
      'params_mismatch' => [{ body: 'Olá {{1}}, seu orçamento {{2}} está pronto' }, 'APPROVED']
    }.each do |reason, (fixture, meta_status)|
      context "when the synced catalogue yields #{reason}" do
        let(:message_templates) { [synced(**fixture)] }

        it 'blocks with the reason, the Meta status and the last sync time' do
          result = described_class.check(inbox: channel.inbox, template: template)

          expect(result).to be_blocked
          expect(result.reason).to eq(reason)
          expect(result.meta_status).to eq(meta_status)
          expect(result.last_synced_at).to eq(last_sync)
        end

        it 'makes the due-attempt job create zero messages' do
          contact = create(:contact, account: account)
          contact_inbox = create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: '5511999999999')
          conversation = create(:conversation, account: account, inbox: channel.inbox, contact: contact, contact_inbox: contact_inbox)
          opportunity = ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
          definition = ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2])
          ScanSolo::TemplateMapping.create!(account: account, stage: 'novo_lead', step: 1, template_name: template.name, language: 'pt_BR',
                                            params: [{ 'source' => 'contact_first_name' }])
          ScanSolo::AiAgentConfig.draft_for!(account).update!(name: 'Agente', enabled: true, allowed_inbox_ids: [channel.inbox.id])
          ScanSolo::AiAgent::PublishService.new(account: account).call
          ScanSolo::ConversationExtension.resolve_for(conversation)
          attempt = ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: definition).attempts.first

          expect do
            ScanSolo::CadenceDueAttemptJob.process_attempt!(attempt, enforce_window: false)
          end.not_to change(Message, :count)
        end
      end
    end

    it 'matches the language case-insensitively and counts repeated placeholders once' do
      channel.update!(message_templates: [synced(language: 'pt_br', body: '{{1}}, lembrete: {{1}}')])

      expect(described_class.check(inbox: channel.inbox, template: template)).not_to be_blocked
    end
  end
end
