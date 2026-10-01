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

  describe 'lead_source (RF-02)' do
    it 'is website for a new conversation whose first message is the incoming one, also in the audit payload' do
      opportunity = described_class.call(message: message).opportunity

      expect(opportunity.reload.lead_source).to eq('website')
      expect(ScanSolo::AuditEvent.find_by!(event_type: 'pipeline.opportunity_created', subject: opportunity).payload)
        .to include('lead_source' => 'website')
    end

    it 'is manual when an agent opened the conversation with a native outgoing message and the customer replied' do
      create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: agent, created_at: 1.hour.ago)

      expect(described_class.call(message: message).opportunity.reload.lead_source).to eq('manual')
    end

    it 'keeps website and manual leads on the same em_contato cadence and relative schedule (RF-01)' do
      manual_conversation = create(:conversation, account: account, contact: create(:contact, account: account), assignee: agent)
      create(:message, account: account, conversation: manual_conversation, message_type: :outgoing, sender: agent, created_at: 1.hour.ago)
      manual_message = create(:message, account: account, conversation: manual_conversation, message_type: :incoming,
                                        sender: manual_conversation.contact)
      ScanSolo::CadenceDefinition.create!(stage: 'em_contato', version: 1, offsets: [24, 48, 72, 96, 120])

      schedules = [message, manual_message].map do |inbound|
        opportunity = described_class.call(message: inbound).opportunity
        ScanSolo::Pipeline::StageTransitionService.new(opportunity: opportunity, target_stage: :em_contato).call
        enrollment = opportunity.cadence_enrollments.active.sole
        [opportunity.lead_source, enrollment.cadence_definition_id,
         enrollment.attempts.order(:step).map { |attempt| attempt.scheduled_at - enrollment.created_at }]
      end

      expect(schedules.map(&:first)).to eq(%w[website manual])
      expect(schedules.map { |schedule| schedule.drop(1) }.uniq.size).to eq(1)
    end
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
