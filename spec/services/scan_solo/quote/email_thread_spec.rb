# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Quote::EmailThread do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_email, account: account, email: 'atendimento.comercial@scansolo.com.br', smtp_enabled: true,
                           smtp_address: 'smtp.example.com', smtp_port: 587, smtp_login: 'login', smtp_password: 'secret')
  end
  let(:inbox) { channel.inbox }
  let(:recipient) { 'comercial@scansolo.com.br' }
  let(:subject_line) { 'Solicitação de orçamento #42 — Solar Ltda' }
  let(:email) { ScanSolo::Quote::EmailComposer::Email.new(subject: subject_line, text: "Linha 1\nLinha 2", html: 'Linha 1<br>Linha 2') }
  let(:conversation) { described_class.open!(inbox: inbox, recipient: recipient, subject: subject_line, marker: 'quote_request') }

  # RNF-04: 0 real SMTP. `config/initializers/mailer.rb` falls back to sendmail without SMTP_ADDRESS, and the
  # channel SMTP settings would switch the message to :smtp, so both stay on ActionMailer :test here.
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
  end

  it 'opens a marked conversation without messages for the recipient contact' do
    expect(conversation).to have_attributes(inbox: inbox, messages: be_empty)
    expect(conversation.additional_attributes).to include('mail_subject' => subject_line, 'scansolo_thread' => 'quote_request')
    expect(conversation.contact).to have_attributes(email: recipient, name: 'Comercial')
  end

  it 'reuses the recipient contact on a second open! with a new conversation' do
    conversation

    second = nil
    expect do
      second = described_class.open!(inbox: inbox, recipient: recipient, subject: 'Pedido de negociação #42', marker: 'negotiation_notification')
    end.not_to change(Contact, :count)

    expect(second).not_to eq(conversation)
    expect(second.contact).to eq(conversation.contact)
    expect(second.additional_attributes['scansolo_thread']).to eq('negotiation_notification')
  end

  it 'delivers one native e-mail from the channel to the recipient with the thread subject (CT-03)' do
    message = nil
    perform_enqueued_jobs(only: SendReplyJob) do
      message = described_class.post!(conversation: conversation, recipient: recipient, email: email)
    end

    expect(message).to have_attributes(message_type: 'outgoing', content: "Linha 1\nLinha 2")
    expect(message.content_attributes).to include('to_emails' => [recipient])
    expect(ActionMailer::Base.deliveries.size).to eq(1)

    mail = ActionMailer::Base.deliveries.last
    expect(mail).to have_attributes(from: ['atendimento.comercial@scansolo.com.br'], to: [recipient], subject: subject_line)
    expect((mail.html_part || mail).body.decoded).to include('Linha 1<br>Linha 2')
    expect(mail.message_id).to start_with("conversation/#{conversation.uuid}/messages/#{message.id}@")
  end

  it 'refuses to create the message inside an open transaction (RNF-01)' do
    conversation

    expect do
      ActiveRecord::Base.transaction { described_class.post!(conversation: conversation, recipient: recipient, email: email) }
    end.to raise_error(CustomExceptions::ScanSolo::DeliveryInsideTransaction)
    expect(conversation.messages.count).to eq(0)
  end
end
