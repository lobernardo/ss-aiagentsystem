# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::AgentAction do
  it 'registers an action with a valid classification' do
    action = described_class.create!(action_id: 'test_action', classification: :automatic, schema: { 'type' => 'object' })

    expect(action).to be_persisted
    expect(action.classification).to eq('automatic')
  end

  it 'exposes exactly the fixed classification vocabulary' do
    expect(described_class.classifications.keys).to contain_exactly(
      'read_only', 'automatic', 'requires_confirmation', 'disabled'
    )
  end

  it 'rejects registering an action with no classification' do
    action = described_class.new(action_id: 'unclassified_action', schema: {})

    expect(action).not_to be_valid
    expect(action.errors[:classification]).to be_present
  end

  it 'rejects a duplicate action_id' do
    described_class.create!(action_id: 'dup_action', classification: :automatic, schema: {})
    duplicate = described_class.new(action_id: 'dup_action', classification: :read_only, schema: {})

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:action_id]).to be_present
  end
end
