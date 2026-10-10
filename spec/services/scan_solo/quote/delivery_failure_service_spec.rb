# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Quote::DeliveryFailureService do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:customer_inbox) { create(:inbox, account: account) }
  let(:email_inbox) { create(:channel_email, account: account, email: 'atendimento.comercial@scansolo.com.br').inbox }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: customer_inbox, contact: contact) }
  let(:email_conversation) { create(:conversation, account: account, inbox: email_inbox) }
  let(:opportunity) { ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado) }
  let!(:quote_request) do
    ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, email_conversation: email_conversation,
                                   correlation_id: SecureRandom.uuid)
  end
  let(:failed_message) do
    create(:message, account: account, conversation: email_conversation, message_type: :outgoing, status: :failed,
                     content_attributes: { 'to_emails' => ['luciano@scansolo.com.br'], 'external_error' => 'SMTP 550 mailbox unavailable' })
  end
  let(:notes) { conversation.messages.where(private: true) }
  let(:audits) { ScanSolo::AuditEvent.where(event_type: 'quote_request.delivery_failed') }
  let(:email_link) { ScanSolo::Quote::EmailComposer.conversation_url(account.id, email_conversation.display_id) }

  before { ScanSolo::AiAgent::PublishService.new(account: account).call }

  def fail_delivery(reason: 'Net::SMTPFatalError', message: nil)
    described_class.call(opportunity: ScanSolo::PipelineOpportunity.find(opportunity.id), reason: reason, message: message)
  end

  describe 'failure before the message exists (RF-18 case A)' do
    it 'creates 1 private note in the WhatsApp conversation with the reason and the e-mail conversation link' do
      fail_delivery

      expect(notes.sole.content).to eq(
        'Não foi possível enviar a solicitação de orçamento ao comercial (motivo: Net::SMTPFatalError). ' \
        "Confira o envio na conversa de e-mail: #{email_link}"
      )
      expect(email_conversation.messages).to be_empty
    end

    it 'records 1 quote_request.delivery_failed with the CT-06 payload and the request correlation id (RF-19)' do
      fail_delivery

      expect(audits.sole).to have_attributes(subject: opportunity, correlation_id: quote_request.correlation_id)
      expect(audits.sole.payload).to eq(
        'quote_request_id' => quote_request.id, 'opportunity_id' => opportunity.id, 'template_version' => 'quote_request_email.v2',
        'recipient' => 'comercial@scansolo.com.br', 'message_id' => nil, 'result' => 'Net::SMTPFatalError'
      )
    end
  end

  describe 'failed message (RF-18 case B)' do
    it 'records the message recipient and id, with the reason truncated to 200 characters' do
      fail_delivery(reason: 'x' * 300, message: failed_message)

      expect(audits.sole.payload).to include('recipient' => 'luciano@scansolo.com.br', 'message_id' => failed_message.id)
      expect(audits.sole.payload['result'].length).to eq(200)
    end

    it 'is idempotent per message: 2 calls → 1 note and 1 audit' do
      2.times { fail_delivery(reason: 'SMTP 550 mailbox unavailable', message: failed_message) }

      expect(notes.count).to eq(1)
      expect(audits.count).to eq(1)
    end
  end

  it 'changes neither the stage, the request status nor the handoff state' do
    fail_delivery

    expect(opportunity.reload).to be_qualificado
    expect(quote_request.reload).to be_awaiting_reply
    expect(ScanSolo::ConversationExtension.resolve_for(conversation)).to be_ai_active
  end

  it 'refuses to run inside an open transaction (RNF-04)' do
    expect { ActiveRecord::Base.transaction { fail_delivery } }.to raise_error(CustomExceptions::ScanSolo::DeliveryInsideTransaction)
    expect(notes).to be_empty
    expect(audits).to be_empty
  end
end
