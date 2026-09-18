# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::AuditLogger do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:user) { create(:user, account: account) }
  let(:correlation_id) { SecureRandom.uuid }

  describe '.record!' do
    it 'persists exactly one audit event row' do
      expect do
        described_class.record!(
          subject: conversation,
          event_type: 'handoff.requested',
          actor: user,
          correlation_id: correlation_id,
          payload: { note: 'takeover' }
        )
      end.to change(ScanSolo::AuditEvent, :count).by(1)
    end

    it 'returns the created, immutable audit event' do
      event = described_class.record!(
        subject: conversation,
        event_type: 'handoff.requested',
        correlation_id: correlation_id
      )

      expect(event).to be_a(ScanSolo::AuditEvent)
      expect(event.subject).to eq(conversation)
      expect(event.correlation_id).to eq(correlation_id)
      expect { event.update(event_type: 'other') }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { event.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end
end
