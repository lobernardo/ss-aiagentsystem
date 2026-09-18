# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::AuditEvent do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:user) { create(:user, account: account) }

  let(:audit_event) do
    described_class.create!(
      subject: conversation,
      actor: user,
      event_type: 'handoff.requested',
      correlation_id: SecureRandom.uuid,
      payload: { reason: 'manual takeover' }
    )
  end

  it 'persists with subject, actor, event type, correlation id and payload' do
    expect(audit_event).to be_persisted
    expect(audit_event.subject).to eq(conversation)
    expect(audit_event.actor).to eq(user)
    expect(audit_event.payload).to eq('reason' => 'manual takeover')
  end

  it 'raises on update' do
    audit_event
    expect { audit_event.update(event_type: 'handoff.cancelled') }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'raises on destroy' do
    audit_event
    expect { audit_event.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'requires an event_type and correlation_id' do
    invalid_event = described_class.new(subject: conversation)

    expect(invalid_event).not_to be_valid
    expect(invalid_event.errors[:event_type]).to be_present
    expect(invalid_event.errors[:correlation_id]).to be_present
  end
end
