# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::CadenceDueAttemptJob do
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

    it 'sends an attempt that is due inside the window' do
      morning = ActiveSupport::TimeZone['America/Sao_Paulo'].local(2026, 1, 5, 10, 0, 0)
      attempt.update!(scheduled_at: morning)

      travel_to(morning + 1.minute) do
        perform_enqueued_jobs { described_class.process_attempt!(attempt.reload) }
      end

      expect(attempt.reload).to be_sent
      expect(attempt.sent_at).to be_present
    end
  end

  describe 'no-duplicate-on-retry (RF-61)' do
    it 'produces zero additional sends when re-run for an already-sent step' do
      morning = ActiveSupport::TimeZone['America/Sao_Paulo'].local(2026, 1, 5, 10, 0, 0)
      attempt.update!(scheduled_at: morning)

      travel_to(morning + 1.minute) do
        perform_enqueued_jobs { described_class.process_attempt!(attempt.reload) }

        expect do
          perform_enqueued_jobs { described_class.process_attempt!(attempt.reload) }
        end.not_to change { Message.where(conversation_id: conversation.id).count }
      end
    end
  end
end
