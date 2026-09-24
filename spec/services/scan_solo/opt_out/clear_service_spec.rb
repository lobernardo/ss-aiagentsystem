# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::OptOut::ClearService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  it 'clears the marker and records one contact.opt_out_cleared audit event with the admin as actor (RF-63)' do
    ScanSolo::OptOut::MarkService.call(contact: contact, source: 'keyword')

    extension = described_class.call(contact: contact, actor: admin)

    expect(extension.opted_out).to be false
    events = ScanSolo::AuditEvent.where(event_type: 'contact.opt_out_cleared')
    expect(events.count).to eq(1)
    expect(events.first).to have_attributes(actor: admin, subject: contact)
  end

  it 'records nothing for a contact that is not opted out' do
    expect { described_class.call(contact: contact, actor: admin) }.not_to change(ScanSolo::AuditEvent, :count)
  end
end
