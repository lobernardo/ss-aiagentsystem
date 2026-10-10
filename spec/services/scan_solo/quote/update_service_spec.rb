# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Quote::UpdateService do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:customer_inbox) { create(:inbox, account: account) }
  let(:email_inbox) do
    create(:channel_email, account: account, email: 'atendimento.comercial@scansolo.com.br', smtp_enabled: true,
                           smtp_address: 'smtp.example.com', smtp_port: 587, smtp_login: 'login', smtp_password: 'secret').inbox
  end
  let(:contact) { create(:contact, account: account, name: 'Ana Souza') }
  let(:conversation) { create(:conversation, account: account, inbox: customer_inbox, contact: contact) }
  let(:opportunity) { ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado) }
  let(:writer) { ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state) }
  let(:draft) { ScanSolo::AiAgentConfig.draft_for!(account) }
  let(:quote_request) { ScanSolo::QuoteRequest.find_by!(opportunity: opportunity) }
  let(:thread_messages) { quote_request.email_conversation.messages }
  let(:updates) { thread_messages.where("additional_attributes ->> 'scansolo_origin' = 'quote_request_update'") }
  let(:notices) { conversation.messages.where("additional_attributes ->> 'scansolo_origin' = 'quote_notice'") }
  let(:audits) { ScanSolo::AuditEvent.where(event_type: 'quote_request.update_sent') }

  # RNF-07: 0 real SMTP (see spec/services/scan_solo/quote/email_thread_spec.rb).
  around do |example|
    original = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :test
    example.run
  ensure
    ActionMailer::Base.delivery_method = original
  end

  before do
    allow_any_instance_of(ConversationReplyMailer).to receive(:set_delivery_method) # rubocop:disable RSpec/AnyInstance
    draft.update!(name: 'Agente', enabled: true, allowed_inbox_ids: [customer_inbox.id], quote_inbox_id: email_inbox.id)
    ScanSolo::AiAgent::PublishService.new(account: account).call
    writer.complete!(at: Time.current)
    writer.record_next_action!(value: 'proposta', source_message_id: nil)
    perform_enqueued_jobs(only: SendReplyJob) { ScanSolo::Quote::RequestService.call(opportunity: opportunity) }
    ActionMailer::Base.deliveries.clear
  end

  def run_service
    perform_enqueued_jobs(only: SendReplyJob) { described_class.call(quote_request: ScanSolo::QuoteRequest.find(quote_request.id)) }
  end

  def inform_depth
    writer.apply_field!(key: 'profundidade', value: '3 m', status: 'confirmado', source_message_id: nil)
  end

  describe 'update e-mail in the request thread (RF-14, CT-03)' do
    before { inform_depth }

    it 'posts 1 message with Re: <mail_subject>, Atualização: first, the Profundidade change, the full summary and the block' do
      expect { run_service }.to change(thread_messages, :count).by(1)

      body = updates.sole.content
      expect(body.lines.first.chomp).to eq('Atualização:')
      expect(body).to include('Profundidade de interesse: não informado → 3 m', 'DADOS DO CLIENTE', 'Comercial ScanSolo')
      expect(body).to end_with(ScanSolo::Quote::EmailComposer.empty_block)
      expect(updates.sole.content_attributes['to_emails']).to eq(['comercial@scansolo.com.br'])

      mail = ActionMailer::Base.deliveries.sole
      expect(mail.subject).to eq("Re: #{quote_request.email_conversation.additional_attributes['mail_subject']}")
    end

    it 'records the update, the new comparison base and quote_request.update_sent with the CT-06 payload (RF-19)' do
      run_service

      message = updates.sole
      expect(quote_request.updates.sole).to have_attributes(message_id: message.id, sent_at: be_present)
      expect(quote_request.reload.rendered_snapshot['fields']['profundidade']['value']).to eq('3 m')
      expect(quote_request.update_window_ends_at).to be_nil
      expect(audits.sole).to have_attributes(subject: opportunity, correlation_id: quote_request.correlation_id)
      expect(audits.sole.payload).to eq(
        'quote_request_id' => quote_request.id, 'opportunity_id' => opportunity.id, 'template_version' => 'quote_request_email.v2',
        'recipient' => 'comercial@scansolo.com.br', 'message_id' => message.id, 'result' => 'sent'
      )
    end

    it 'never notifies the customer, opens no request or thread and keeps the status (OC/RF-53)' do
      expect { run_service }.not_to change(ScanSolo::QuoteRequest, :count)

      expect(notices.count).to eq(1)
      expect(email_inbox.conversations.count).to eq(1)
      expect(quote_request.reload).to be_awaiting_reply
    end

    it 'is idempotent: running it again keeps 1 update e-mail' do
      2.times { run_service }

      expect(updates.count).to eq(1)
      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(audits.count).to eq(1)
    end

    it 'sends 1 e-mail for 2 concurrent threads (RNF-05)' do
      Array.new(2) { Thread.new { run_service } }.each(&:join)

      expect(updates.count).to eq(1)
      expect(ActionMailer::Base.deliveries.size).to eq(1)
    end

    it 'also goes out while a correction is requested' do
      quote_request.update!(status: :correction_requested)

      run_service

      expect(updates.count).to eq(1)
      expect(quote_request.reload).to be_correction_requested
    end

    it 'sends nothing once the reply was processed (replied), closing the window' do
      quote_request.update!(status: :replied, update_window_ends_at: 1.minute.from_now)

      expect { run_service }.not_to change(Message, :count)
      expect(quote_request.reload.update_window_ends_at).to be_nil
      expect(quote_request.updates).to be_empty
    end

    it 'releases the version claim when the post fails, so the retry sends it once (RF-18 case A)' do
      allow(ScanSolo::Quote::EmailThread).to receive(:post!).and_raise(Net::SMTPServerBusy, 'smtp down')
      expect { described_class.call(quote_request: quote_request) }.to raise_error(Net::SMTPServerBusy)
      expect(ScanSolo::QuoteRequestUpdate.where(quote_request_id: quote_request.id)).to be_empty

      allow(ScanSolo::Quote::EmailThread).to receive(:post!).and_call_original
      run_service

      expect(updates.count).to eq(1)
    end
  end

  it 'sends nothing when no rendered value changed' do
    writer.apply_field!(key: 'telefone', value: '11 99999-0000', status: 'confirmado', source_message_id: nil)

    expect { run_service }.not_to change(Message, :count)
    expect(quote_request.updates).to be_empty
    expect(audits).to be_empty
  end

  it 'sends nothing for a request sent before the rendered snapshot existed' do
    inform_depth
    quote_request.update!(rendered_snapshot: nil, rendered_digest: nil)

    expect { run_service }.not_to change(Message, :count)
  end

  it 'lists and attaches a new lead attachment (RF-13, CT-03)' do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('a' * 2.megabytes), filename: 'croqui.pdf', content_type: 'application/pdf')
    create(:message, account: account, conversation: conversation, message_type: :incoming)
      .attachments.create!(account_id: account.id, file_type: :file, file: blob)

    run_service

    message = updates.sole
    expect(message.content).to include('Novo anexo: croqui.pdf (PDF)', '- croqui.pdf (PDF) — anexado a este e-mail.')
    expect(message.attachments.sole.file.blob.checksum).to eq(blob.checksum)
    expect(ActionMailer::Base.deliveries.sole.attachments.sole).to have_attributes(filename: 'croqui.pdf')
  end
end
