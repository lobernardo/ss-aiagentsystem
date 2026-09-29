require 'rails_helper'

RSpec.describe ScanSolo::LeadState::InitializeService do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, name: 'Milena (WhatsApp)', email: nil, phone_number: nil, custom_attributes: {}) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) { ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation) }
  let(:lead_state) { opportunity.reload.lead_state }

  it 'seeds the 34 catalog fields from the contact on creation: nome inferido, the other 33 faltante (RF-01)' do
    expect(lead_state.fields.keys).to match_array(ScanSolo::Qualification::FieldResolver::CATALOG_KEYS)
    expect(lead_state.fields['nome']).to include('value' => 'Milena (WhatsApp)', 'status' => 'inferido', 'source_message_id' => nil)
    expect(lead_state.fields.except('nome').values).to all(include('value' => nil, 'status' => 'faltante'))
    expect(lead_state).to be_em_andamento
    expect(lead_state.next_action).to be_nil
    expect(lead_state.events.sole).to have_attributes(subject: 'field', key: 'nome', previous_status: 'faltante', new_status: 'inferido')
  end

  it 'never leaves a faltante field with a value nor a confirmado/inferido field without one' do
    contact.update!(email: 'milena@example.com', custom_attributes: { 'Área ou extensão' => '800 m²', 'cidade' => '' })

    fields = lead_state.fields.values
    expect(fields.select { |field| field['status'] == 'faltante' }.pluck('value')).to all(be_nil)
    expect(fields.reject { |field| field['status'] == 'faltante' }.pluck('value')).to all(be_present)
    expect(lead_state.fields.select { |_key, field| field['status'] == 'inferido' }.keys).to contain_exactly('nome', 'email', 'area')
  end

  it 'leaves an existing lead state untouched when called again' do
    ScanSolo::LeadState::Writer.new(lead_state: lead_state).apply_field!(key: 'area', value: '800 m²', status: 'confirmado', source_message_id: nil)

    expect { described_class.call(opportunity: opportunity) }.not_to(change { [lead_state.reload.attributes, lead_state.events.count] })
    expect(ScanSolo::LeadState.where(opportunity_id: opportunity.id).count).to eq(1)
  end

  it 'starts em_andamento without a next action even when the opportunity is created in ganho (RF-01)' do
    won_conversation = create(:conversation, account: account, contact: contact)
    won = ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: won_conversation, stage: :ganho)

    expect(won.reload.lead_state).to have_attributes(qualification_status: 'em_andamento', next_action: nil, qualification_completed_at: nil)
  end

  it 'writes nothing to the contact' do
    contact.update!(custom_attributes: { 'area' => '800 m²' })

    expect { opportunity }.not_to(change { contact.reload.attributes })
  end
end
