# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Pipeline::OpportunityBootstrapService do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, contact: contact, assignee: agent) }
  let(:message) { create(:message, account: account, conversation: conversation, message_type: :incoming, sender: contact) }

  before { ScanSolo::CadenceDefinition.create!(stage: 'novo_lead', version: 1, offsets: [2, 24, 48, 96]) }

  it 'creates one novo_lead opportunity owned by the assignee, one Novo Lead enrollment and one audit event (RF-22, RF-24)' do
    result = described_class.call(message: message)

    opportunity = result.opportunity
    expect(result).to be_created
    expect(opportunity).to have_attributes(stage: 'novo_lead', account: account, contact: contact, owner: agent)
    expect(opportunity.last_customer_interaction_at).to be_within(1.second).of(message.created_at)
    expect(opportunity.cadence_enrollments.active.sole.cadence_definition.stage).to eq('novo_lead')
    expect(ScanSolo::AuditEvent.where(event_type: 'pipeline.opportunity_created', subject: opportunity).count).to eq(1)
  end

  it 'leaves the owner empty when the conversation has no assignee' do
    conversation.update!(assignee: nil)

    expect(described_class.call(message: message).opportunity.owner_id).to be_nil
  end

  it 'converges a second (racing) call on the same row through the unique conversation index' do
    first = described_class.call(message: message)
    second = described_class.call(message: message)

    expect(second).not_to be_created
    expect(second.opportunity.id).to eq(first.opportunity.id)
    expect(ScanSolo::PipelineOpportunity.where(conversation_id: conversation.id).count).to eq(1)
    expect(ScanSolo::CadenceEnrollment.count).to eq(1)
    expect(ScanSolo::AuditEvent.where(event_type: 'pipeline.opportunity_created').count).to eq(1)
  end

  context 'with a contact that only has its WhatsApp profile name (lead state RF-01)' do
    let(:contact) { create(:contact, account: account, name: 'Milena (WhatsApp)', email: nil, phone_number: nil, custom_attributes: {}) }

    it 'creates one lead state with the 34 catalog fields and keeps it single on a second bootstrap' do
      first = described_class.call(message: message)
      described_class.call(message: message)

      lead_state = ScanSolo::LeadState.where(opportunity_id: first.opportunity.id).sole
      expect(lead_state.fields.size).to eq(34)
      expect(lead_state.fields['nome']).to include('value' => 'Milena (WhatsApp)', 'status' => 'inferido')
      expect(lead_state.fields.values.count { |field| field['status'] == 'faltante' && field['value'].nil? }).to eq(33)
      expect(lead_state).to be_em_andamento
      expect(ScanSolo::LeadState.count).to eq(1)
    end
  end
end
