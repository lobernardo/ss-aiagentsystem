# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::CadenceDueAttemptJob do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :novo_lead)
  end
  let(:offsets) { [2] }
  let(:cadence_definition) { ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: offsets) }
  let(:enrollment) { ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: cadence_definition) }
  let(:attempt) { enrollment.attempts.order(:step).first }
  let(:morning) { ActiveSupport::TimeZone['America/Sao_Paulo'].local(2026, 1, 5, 10, 0, 0) }
  let(:conversation_messages) { Message.where(conversation_id: conversation.id) }

  before do
    stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook')
    ScanSolo::AiAgentConfig.draft_for!(account).update!(name: 'Agente', enabled: true, allowed_inbox_ids: [inbox.id])
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  describe 'registration (RF-60)' do
    it 'is registered in config/schedule.yml as a sidekiq-cron entry, not an external scheduler' do
      schedule = YAML.load_file(Rails.root.join('config/schedule.yml'))

      entry = schedule['scan_solo_cadence_due_attempt_job']
      expect(entry).to be_present
      expect(entry['class']).to eq('ScanSolo::CadenceDueAttemptJob')
    end
  end

  describe 'sending window (RF-58)' do
    it 'does not send an attempt computed for 21:00 America/Sao_Paulo, deferring it to the next 09:00' do
      evening = ActiveSupport::TimeZone['America/Sao_Paulo'].local(2026, 1, 5, 21, 0, 0)
      attempt.update!(scheduled_at: evening)

      travel_to(evening + 5.minutes) do
        described_class.process_attempt!(attempt.reload)
      end

      attempt.reload
      expect(attempt).to be_scheduled
      expect(attempt.scheduled_at).to eq(ActiveSupport::TimeZone['America/Sao_Paulo'].local(2026, 1, 6, 9, 0, 0))
    end

    it 'dispatches an in-window due attempt within one cron cycle, never marking it sent (RNF-08, RF-27)' do
      attempt.update!(scheduled_at: morning)

      travel_to(morning + 5.minutes) { described_class.perform_now }

      attempt.reload
      expect(attempt).to be_dispatched
      expect(attempt.message).to eq(conversation_messages.outgoing.last)
      expect(attempt.message.additional_attributes['scansolo_origin']).to eq('cadence')
      expect(attempt.sent_at).to be_nil
    end
  end

  describe 'no-duplicate-on-retry (RF-61)' do
    it 'never re-sends a dispatched attempt' do
      attempt.update!(scheduled_at: morning)

      travel_to(morning + 1.minute) do
        described_class.process_attempt!(attempt.reload)

        expect { described_class.perform_now }.not_to change(conversation_messages, :count)
      end
      expect(attempt.reload).to be_dispatched
    end
  end

  describe 'kill switch (RF-04)' do
    it 'sends nothing and consumes nothing while the account flag is off' do
      attempt.update!(scheduled_at: morning)
      account.update!(scansolo_enabled: false)

      travel_to(morning + 1.minute) do
        expect { described_class.perform_now }.not_to change(conversation_messages, :count)
      end

      attempt.reload
      expect(attempt).to be_scheduled
      expect(attempt.scheduled_at).to eq(morning)
      expect(enrollment.reload).to have_attributes(status: 'active', current_step: 0)
    end
  end

  describe 'prechecks (RF-26)' do
    before { attempt.update!(scheduled_at: morning) }

    it 'cancels the enrollment of an opted-out contact with reason opt_out' do
      ScanSolo::ContactExtension.resolve_for(contact).update!(opted_out: true)

      travel_to(morning + 1.minute) { described_class.perform_now }

      expect(attempt.reload).to have_attributes(result: 'cancelled', last_block_reason: 'opt_out')
      expect(enrollment.reload).to be_cancelled
      expect(conversation_messages.count).to eq(0)
    end

    it 'cancels the enrollment of a resolved conversation with reason conversation_resolved' do
      conversation.update!(status: :resolved)

      travel_to(morning + 1.minute) { described_class.perform_now }

      expect(attempt.reload).to have_attributes(result: 'cancelled', last_block_reason: 'conversation_resolved')
      expect(enrollment.reload).to be_cancelled
    end

    it '(3) defers without consuming while a human controls the conversation' do
      ScanSolo::ConversationExtension.resolve_for(conversation).update!(ai_control_state: :human_active)

      travel_to(morning + 1.minute) do
        expect { described_class.perform_now }.not_to change(conversation_messages, :count)
      end

      expect(attempt.reload).to have_attributes(result: 'scheduled', last_block_reason: 'human_controlled', scheduled_at: morning)
      expect(attempt.last_checked_at).to eq(morning + 1.minute)
      expect(enrollment.reload.current_step).to eq(0)
    end

    context 'with (4) an unavailable WhatsApp template' do
      let(:channel) { create(:channel_whatsapp, account: account, sync_templates: false, message_templates: []) }
      let(:inbox) { channel.inbox }
      let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511977776666') }
      let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }

      it 'defers without consuming' do
        travel_to(morning + 1.minute) do
          expect { described_class.perform_now }.not_to change(conversation_messages, :count)
        end

        expect(attempt.reload).to have_attributes(result: 'scheduled', last_block_reason: 'template_missing')
        expect(enrollment.reload.current_step).to eq(0)
      end
    end
  end

  describe 'a WhatsApp send' do
    before do
      stub_request(:post, 'https://waba.360dialog.io/v1/messages').to_return(
        status: 200, body: { messages: [{ id: 'wamid.cadence' }] }.to_json, headers: { 'Content-Type' => 'application/json' }
      )
    end

    let(:channel) do
      create(:channel_whatsapp, account: account, sync_templates: false, message_templates: [
               { 'name' => 'scansolo_cadence_novo_lead_v1_step1', 'status' => 'APPROVED', 'language' => 'pt_BR',
                 'namespace' => 'ns', 'components' => [{ 'type' => 'BODY', 'text' => 'Oi, tudo bem?' }] }
             ])
    end
    let(:inbox) { channel.inbox }
    let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511966665555') }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }

    it 'records dispatched with the native message id, then sent once the native transport gets a provider id' do
      attempt.update!(scheduled_at: morning)

      travel_to(morning + 1.minute) { described_class.perform_now }

      attempt.reload
      expect(attempt).to be_dispatched
      expect(attempt.message_id).to eq(conversation_messages.outgoing.last.id)
      expect(attempt.message.additional_attributes['template_params']).to include('name' => 'scansolo_cadence_novo_lead_v1_step1',
                                                                                  'language' => 'pt_BR')

      # SendReplyJob stores the provider id; its message_updated event then reaches the listener.
      2.times { perform_enqueued_jobs(only: [SendReplyJob, EventDispatcherJob]) }

      expect(attempt.message.reload.source_id).to eq('wamid.cadence')
      expect(attempt.reload).to be_sent
      expect(attempt.sent_at).to be_present
    end
  end

  describe 'deferral shift (RF-29)' do
    let(:offsets) { [2, 24] }

    it 'shifts later attempts by the delay of a deferred send and sends at most one attempt per enrollment per run' do
      first_attempt = attempt
      second_attempt = enrollment.attempts.order(:step).second
      first_attempt.update!(scheduled_at: morning)
      second_attempt.update!(scheduled_at: morning + 22.hours)
      extension = ScanSolo::ConversationExtension.resolve_for(conversation)
      extension.update!(ai_control_state: :human_active)

      travel_to(morning + 1.minute) { described_class.perform_now }
      expect(first_attempt.reload).to be_scheduled

      extension.update!(ai_control_state: :ai_active)
      travel_to(morning + 26.hours) do
        expect { described_class.perform_now }.to change(conversation_messages, :count).by(1)
      end

      expect(first_attempt.reload).to be_dispatched
      expect(second_attempt.reload).to be_scheduled
      expect(second_attempt.scheduled_at).to eq(morning + 48.hours)
      expect(enrollment.reload.current_step).to eq(1)
    end
  end
end
