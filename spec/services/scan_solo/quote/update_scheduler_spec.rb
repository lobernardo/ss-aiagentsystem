# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Quote::UpdateScheduler do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) { ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation) }
  let(:request_message) { create(:message, account: account, conversation: conversation, message_type: :outgoing) }
  let!(:quote_request) do
    ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid,
                                   request_message_id: request_message.id)
  end
  let(:start) { Time.zone.local(2026, 10, 10, 9, 0, 0) }
  let(:update_jobs) { enqueued_jobs.select { |job| job[:job] == ScanSolo::QuoteRequestUpdateJob } }

  def schedule
    described_class.call(opportunity: ScanSolo::PipelineOpportunity.find(opportunity.id))
  end

  it 'opens 1 fixed window for changes at t=0, 2 and 9 min, with its job at t=10 min (RF-14 (b))' do
    [0, 2, 9].each { |minute| travel_to(start + minute.minutes) { schedule } }

    expect(update_jobs.size).to eq(1)
    expect(update_jobs.sole).to include(args: [quote_request.id], at: (start + 10.minutes).to_f)
    expect(quote_request.reload.update_window_ends_at).to eq(start + 10.minutes)
  end

  it 'opens a new window for a change at t=11 after the job ran at t=10' do
    travel_to(start) { schedule }
    travel_to(start + 10.minutes) { ScanSolo::Quote::UpdateService.call(quote_request: quote_request.reload) }
    travel_to(start + 11.minutes) { schedule }

    expect(update_jobs.map { |job| job[:at] }).to eq([(start + 10.minutes).to_f, (start + 21.minutes).to_f])
    expect(quote_request.reload.update_window_ends_at).to eq(start + 21.minutes)
  end

  it 'enqueues nothing once the reply was processed (replied)' do
    quote_request.update!(status: :replied)

    schedule

    expect(update_jobs).to be_empty
    expect(quote_request.reload.update_window_ends_at).to be_nil
  end

  it 'enqueues nothing before the request e-mail was sent' do
    quote_request.update!(request_message_id: nil)

    schedule

    expect(update_jobs).to be_empty
  end

  it 'enqueues nothing for an opportunity without a quote request' do
    quote_request.destroy!

    expect { schedule }.not_to raise_error
    expect(update_jobs).to be_empty
  end

  it 'enqueues 1 job for 2 concurrent calls (RNF-05)' do
    Array.new(2) { Thread.new { schedule } }.each(&:join)

    expect(update_jobs.size).to eq(1)
  end
end
