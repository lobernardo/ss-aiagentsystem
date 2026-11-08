# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::ReportSnapshot do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:week_start) { Date.new(2026, 11, 2) }
  let(:attributes) { { week_start: week_start, payload: { 'period' => 'week' }, generated_at: Time.current } }

  it 'is valid with account, week_start, payload and generated_at' do
    expect(described_class.new(account: account, **attributes)).to be_valid
  end

  it 'requires week_start, payload and generated_at' do
    snapshot = described_class.new(account: account)

    expect(snapshot).not_to be_valid
    expect(snapshot.errors.attribute_names).to include(:week_start, :payload, :generated_at)
  end

  it 'allows one snapshot per (account, week_start) (CT-05)' do
    described_class.create!(account: account, **attributes)
    duplicate = described_class.new(account: account, **attributes)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:week_start]).to be_present
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'allows the same week_start for another account and another week for the same account' do
    described_class.create!(account: account, **attributes)

    expect(described_class.new(account: other_account, **attributes)).to be_valid
    expect(described_class.new(account: account, **attributes, week_start: week_start - 7)).to be_valid
  end
end
