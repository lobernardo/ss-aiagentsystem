# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Proposal::LeadEmailReplyService do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:customer_inbox) { create(:inbox, account: account) }
  let(:email_inbox) { create(:channel_email, account: account, email: 'atendimento.comercial@scansolo.com.br').inbox }
  let(:contact) { create(:contact, account: account, name: 'Ana Souza', email: 'ana@cliente.com.br') }
  let(:conversation) { create(:conversation, account: account, inbox: customer_inbox, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :proposta_enviada)
  end
  let!(:quote_request) do
    ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid, status: :replied)
  end
  let(:proposal_conversation) do
    ScanSolo::Quote::EmailThread.open!(inbox: email_inbox, recipient: contact.email, subject: 'Proposta SS-1', marker: 'proposal_delivery')
  end
  let!(:proposal) { ScanSolo::Proposal.create!(opportunity: opportunity, email_conversation: proposal_conversation) }
  let(:definition) { ScanSolo::CadenceDefinition.create!(stage: 'proposta_enviada', version: 1, offsets: [24, 48, 72]) }
  let!(:enrollment) do
    travel_to(1.hour.ago) { ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: definition) }
  end
  let(:audits) { ScanSolo::AuditEvent.where(event_type: described_class::EVENT_TYPE) }

  def reply(sender)
    create(:message, account: account, inbox: email_inbox, conversation: proposal_conversation, message_type: :incoming,
                     sender: sender, content: 'Recebi a proposta, obrigado.')
  end

  it 'links the lead reply to the opportunity without a QuoteReply, an opportunity or an AI turn (RF-16)' do
    message = reply(contact)

    expect { described_class.call(message: message) }
      .to not_change(ScanSolo::QuoteReply, :count)
      .and not_change(ScanSolo::PipelineOpportunity, :count)
      .and(not_change(ScanSolo::AiTurn, :count))

    expect(opportunity.reload.last_customer_interaction_at).to be_within(1.second).of(message.created_at)
    expect(audits.sole).to have_attributes(
      subject: opportunity, correlation_id: quote_request.correlation_id,
      payload: { 'proposal_id' => proposal.id, 'message_id' => message.id }
    )
  end

  it 'records a single audit when the same message is processed again (RNF-06)' do
    message = reply(contact)

    2.times { described_class.call(message: message) }

    expect(audits.count).to eq(1)
  end

  it 'cancels every scheduled attempt in proposta_enviada (RF-18)' do
    described_class.call(message: reply(contact))

    expect(enrollment.attempts.pluck(:result)).to eq(%w[cancelled cancelled cancelled])
    expect(ScanSolo::AuditEvent.where(event_type: ScanSolo::Cadence::ReplyInterruptionService::EVENT_TYPE).count).to eq(3)
  end

  it 'has no effect for a reply from another sender, such as the commercial CC (Q-04)' do
    commercial = create(:contact, account: account, email: 'comercial@scansolo.com.br')
    message = reply(commercial)

    expect { described_class.call(message: message) }.not_to(change { opportunity.reload.last_customer_interaction_at })

    expect(enrollment.attempts.pluck(:result)).to eq(%w[scheduled scheduled scheduled])
    expect(audits.count).to eq(0)
    expect(ScanSolo::QuoteReply.count).to eq(0)
  end
end
