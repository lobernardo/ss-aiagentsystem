# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::QuoteRequestUpdateJob do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:customer_inbox) { create(:inbox, account: account) }
  let(:email_inbox) { create(:channel_email, account: account, email: 'atendimento.comercial@scansolo.com.br').inbox }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: customer_inbox, contact: contact) }
  let(:opportunity) { ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado) }
  let(:writer) { ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state) }
  let(:draft) { ScanSolo::AiAgentConfig.draft_for!(account) }
  let(:quote_request) { ScanSolo::QuoteRequest.find_by!(opportunity: opportunity) }
  let(:updates) { quote_request.email_conversation.messages.where("additional_attributes ->> 'scansolo_origin' = 'quote_request_update'") }
  let(:notes) { conversation.messages.where(private: true) }
  let(:failures) { ScanSolo::AuditEvent.where(event_type: 'quote_request.delivery_failed') }
  let(:attempts) { [] }

  before do
    draft.update!(name: 'Agente', enabled: true, allowed_inbox_ids: [customer_inbox.id], quote_inbox_id: email_inbox.id)
    ScanSolo::AiAgent::PublishService.new(account: account).call
    writer.complete!(at: Time.current)
    writer.record_next_action!(value: 'proposta', source_message_id: nil)
    ScanSolo::Quote::RequestService.call(opportunity: opportunity)
    writer.apply_field!(key: 'profundidade', value: '3 m', status: 'confirmado', source_message_id: nil)
    freeze_time
  end

  def run_job
    perform_enqueued_jobs(only: described_class) { described_class.perform_later(quote_request.id) }
  end

  def fail_attempts(count)
    allow(ScanSolo::Quote::EmailThread).to receive(:post!).and_wrap_original do |original, **kwargs|
      attempts << Time.current
      raise Net::SMTPServerBusy, 'smtp down' if attempts.size <= count

      original.call(**kwargs)
    end
  end

  context 'when every attempt fails (RF-18 case A)' do
    before { fail_attempts(4) }

    it 'runs exactly 4 attempts, retried 1, 5 and 15 minutes after each failure' do
      run_job

      expect(attempts.size).to eq(4)
      scheduled_at = performed_jobs.select { |job| job[:job] == described_class }.pluck(:at)
      expect(scheduled_at.drop(1)).to eq([1.minute, 5.minutes, 15.minutes].map { |wait| (Time.current + wait).to_f })
    end

    it 'then posts 1 private note and records 1 delivery_failed, with no update e-mail' do
      run_job

      expect(notes.count).to eq(1)
      expect(failures.sole).to have_attributes(correlation_id: quote_request.correlation_id)
      expect(failures.sole.payload).to include('message_id' => nil, 'result' => 'Net::SMTPServerBusy')
      expect(updates).to be_empty
      expect(quote_request.updates).to be_empty
    end
  end

  context 'when only the first attempt fails' do
    before { fail_attempts(1) }

    it 'sends 1 update e-mail on the retry, with no note and no delivery_failed' do
      run_job

      expect(attempts.size).to eq(2)
      expect(updates.count).to eq(1)
      expect(quote_request.updates.sole.message_id).to eq(updates.sole.id)
      expect(notes).to be_empty
      expect(failures).to be_empty
    end
  end
end
