# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Notifications::Publisher do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, stage: :negociacao,
                                          conversation: create(:conversation, account: account, contact: contact))
  end
  let(:payload) { { account_id: account.id, opportunity_id: opportunity.id, correlation_id: SecureRandom.uuid, stage: 'negociacao' } }
  let(:received) { [] }
  let(:recording_adapter) do
    calls = received
    Class.new do
      define_singleton_method(:name) { 'RecordingAdapter' }
      define_singleton_method(:call) do |event:, payload:|
        calls << [event, payload]
        ScanSolo::Notifications::Publisher::Result.new(success: true, reason: nil)
      end
    end
  end
  let(:raising_adapter) do
    Class.new do
      define_singleton_method(:name) { 'RaisingAdapter' }
      define_singleton_method(:call) { |**| raise 'smtp down' }
    end
  end
  let(:failing_adapter) do
    Class.new do
      define_singleton_method(:name) { 'FailingAdapter' }
      define_singleton_method(:call) { |**| ScanSolo::Notifications::Publisher::Result.new(success: false, reason: 'quote_inbox_missing') }
    end
  end

  before { allow(ChatwootExceptionTracker).to receive(:new).and_call_original }

  def publish(*adapters)
    described_class.call(event: 'negotiation.requested', payload: payload, adapters: adapters)
  end

  it 'uses the e-mail adapter by default (RF-41)' do
    expect(described_class::ADAPTERS).to eq([ScanSolo::Notifications::EmailAdapter])
  end

  it 'delivers the identical payload to the adapter and records the success' do
    publish(recording_adapter)

    expect(received).to eq([['negotiation.requested', payload]])
    expect(received.sole.last).to equal(payload)
    expect(ScanSolo::AuditEvent.sole).to have_attributes(
      event_type: 'negotiation.notification_sent', subject: opportunity, correlation_id: payload[:correlation_id],
      payload: { 'adapter' => 'RecordingAdapter' }
    )
  end

  it 'records one failure and reports the exception of a raising adapter without propagating (RF-39)' do
    expect { publish(raising_adapter, recording_adapter) }.not_to raise_error

    expect(ScanSolo::AuditEvent.where(event_type: 'negotiation.notification_failed').sole)
      .to have_attributes(subject: opportunity, payload: { 'adapter' => 'RaisingAdapter', 'reason' => 'smtp down' })
    expect(ChatwootExceptionTracker).to have_received(:new).with(an_instance_of(RuntimeError), account: account).once
    expect(received.size).to eq(1)
  end

  it 'records a failed result with its reason' do
    expect { publish(failing_adapter) }.not_to raise_error

    expect(ScanSolo::AuditEvent.sole)
      .to have_attributes(event_type: 'negotiation.notification_failed',
                          payload: { 'adapter' => 'FailingAdapter', 'reason' => 'quote_inbox_missing' })
    expect(ChatwootExceptionTracker).to have_received(:new)
      .with(an_instance_of(CustomExceptions::ScanSolo::NegotiationNotificationFailed), account: account).once
  end
end
