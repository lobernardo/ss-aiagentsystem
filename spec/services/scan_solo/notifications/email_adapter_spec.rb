# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Notifications::EmailAdapter do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:customer_inbox) { create(:inbox, account: account) }
  let(:email_inbox) do
    create(:channel_email, account: account, email: 'atendimento.comercial@scansolo.com.br', smtp_enabled: true,
                           smtp_address: 'smtp.example.com', smtp_port: 587, smtp_login: 'login', smtp_password: 'secret').inbox
  end
  let(:payload) do
    {
      account_id: account.id, opportunity_id: 42, conversation_id: 7, conversation_url: 'https://app.example.com/app/accounts/1/conversations/9',
      contact: { name: 'Ana Souza', company: 'Solar Ltda', phone: '+5511987654321' }, stage: 'negociacao',
      request_summary: 'Consegue 10% de desconto?',
      proposal: { version_number: 2, proposal_number: 'SS-2026-000012', status: 'sent', document_url: 'https://app.example.com/pdf' },
      current_value: { amount: 12_500.0, currency: 'BRL' },
      recent_messages: [{ sender: 'customer', content: 'Recebi a proposta', created_at: '2026-10-01T12:00:00Z' }],
      correlation_id: 'abc'
    }
  end

  # RNF-04: 0 real SMTP (see spec/services/scan_solo/quote/email_thread_spec.rb).
  around do |example|
    original = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :test
    example.run
  ensure
    ActionMailer::Base.delivery_method = original
  end

  before do
    allow_any_instance_of(ConversationReplyMailer).to receive(:set_delivery_method) # rubocop:disable RSpec/AnyInstance
    ActionMailer::Base.deliveries.clear
    ScanSolo::AiAgentConfig.draft_for!(account).update!(name: 'Agente', enabled: true, allowed_inbox_ids: [customer_inbox.id],
                                                        quote_inbox_id: email_inbox.id, quote_recipient_email: 'luciano@scansolo.com.br')
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  def call
    perform_enqueued_jobs(only: SendReplyJob) { described_class.call(event: 'negotiation.requested', payload: payload) }
  end

  it 'sends one e-mail with the 9 items and the link to the published recipient, in its own thread' do
    expect(call).to be_success

    message = email_inbox.messages.sole
    expect(message).to have_attributes(message_type: 'outgoing')
    expect(message.content_attributes['to_emails']).to eq(['luciano@scansolo.com.br'])
    expect(message.conversation.additional_attributes).to include('scansolo_thread' => 'negotiation_notification')
    expect(message.content).to include(
      'Nome: Ana Souza', 'Empresa: Solar Ltda', 'Telefone: +5511987654321', 'Oportunidade: #42', 'Etapa: Negociação',
      'Conversa no Chatwoot: https://app.example.com/app/accounts/1/conversations/9', 'Resumo do pedido: Consegue 10% de desconto?',
      'Proposta vigente: Versão 2', 'Valor vigente: BRL 12.500,00', 'Cliente: Recebi a proposta'
    )
    expect(ActionMailer::Base.deliveries.sole).to have_attributes(to: ['luciano@scansolo.com.br'],
                                                                  subject: 'Pedido de negociação #42 — Solar Ltda')
  end

  it 'opens a new thread for each notification' do
    2.times { call }

    expect(email_inbox.conversations.count).to eq(2)
  end

  it 'answers failure with the reason when the quote inbox is missing' do
    ScanSolo::AiAgentConfig.draft_for!(account).update!(quote_inbox_id: nil)
    ScanSolo::AiAgent::PublishService.new(account: account).call

    result = call

    expect(result).not_to be_success
    expect(result.reason).to eq('quote_inbox_missing')
    expect(Message.where(inbox: email_inbox)).to be_empty
  end
end
