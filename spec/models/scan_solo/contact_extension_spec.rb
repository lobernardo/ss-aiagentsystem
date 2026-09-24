require 'rails_helper'

RSpec.describe ScanSolo::ContactExtension do
  let(:contact) { create(:contact) }

  it 'resolves one persistent marker per contact, defaulting to no opt-out' do
    extension = described_class.resolve_for(contact)

    expect(extension).not_to be_opted_out
    expect(described_class.resolve_for(contact)).to eq(extension)
    extension.update!(opted_out: true, opted_out_at: Time.current, opted_out_source: 'keyword')
    expect(described_class.resolve_for(contact)).to be_opted_out
  end
end
