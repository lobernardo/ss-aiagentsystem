require 'rails_helper'

RSpec.describe ScanSolo::LeadStateEvent do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) { ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation) }
  let(:state) { opportunity.lead_state }
  let(:event) { state.events.create!(subject: 'field', key: 'nome', new_value: 'Ana', new_status: 'confirmado') }

  it 'allows creating history with only a creation timestamp' do
    expect(event.reload).to have_attributes(lead_state: state, new_value: 'Ana', new_status: 'confirmado')
    expect(event.created_at).to be_present
    expect(event.attributes).not_to have_key('updated_at')
  end

  it 'accepts only the three history subjects' do
    %w[field intent next_action].each do |subject|
      expect(state.events.build(subject: subject)).to be_valid
    end
    expect(state.events.build(subject: 'invalid')).not_to be_valid
    expect(state.events.build(subject: nil)).not_to be_valid
  end

  it 'requires a lead state' do
    expect(described_class.new(subject: 'field')).not_to be_valid
  end

  it 'rejects updates to persisted history' do
    expect { event.update!(new_value: 'Maria') }.to(raise_error { |error| expect(error.class.name).to eq('ActiveRecord::ReadOnlyRecord') })
    expect(event.reload.new_value).to eq('Ana')
  end

  it 'rejects destruction of persisted history' do
    expect { event.destroy }.to(raise_error { |error| expect(error.class.name).to eq('ActiveRecord::ReadOnlyRecord') })
    expect(described_class.exists?(event.id)).to be true
  end
end
