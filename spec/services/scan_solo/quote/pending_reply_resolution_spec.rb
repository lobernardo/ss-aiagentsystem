# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Quote::PendingReplyResolution do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:customer_inbox) { create(:inbox, account: account) }
  let(:email_inbox) do
    create(:channel_email, account: account, email: 'atendimento.comercial@scansolo.com.br', smtp_enabled: true,
                           smtp_address: 'smtp.example.com', smtp_port: 587, smtp_login: 'login', smtp_password: 'secret').inbox
  end
  let(:contact) { create(:contact, account: account, name: 'Ana Souza') }
  let(:conversation) { create(:conversation, account: account, inbox: customer_inbox, contact: contact) }
  let(:opportunity) { ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :qualificado) }
  let(:writer) { ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state) }
  let(:quote_request) { ScanSolo::QuoteRequest.find_by!(opportunity: opportunity) }
  let(:loose_conversation) { create(:conversation, account: account, inbox: email_inbox) }
  let(:scenario_url) { 'https://hook.make.example/scenario-webhook' }
  let(:valid_block) do
    <<~TEXT
      === RESPOSTA DO ORÇAMENTO ===
      Valor total: R$ 12.500,00
      Prazo/cronograma: 30 dias
      Escopo/atividades: Sondagem SPT
      Condições de pagamento: 50% na assinatura
      === FIM ===
    TEXT
  end
  let(:quote_reply) do
    message = create(:message, account: account, inbox: email_inbox, conversation: loose_conversation, message_type: :incoming,
                               sender: loose_conversation.contact, content: valid_block)
    ScanSolo::Quote::ReplyProcessor.call(message: message)
    ScanSolo::QuoteReply.find_by!(message: message)
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
    allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :scenario_url).and_return(scenario_url)
    allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :secret).and_return('make-outbound-secret')
    allow(Rails.application.credentials).to receive(:dig).with(:scan_solo, :make, :inbound_signing_secret).and_return('make-inbound-secret')
    stub_request(:post, scenario_url).to_return(status: 200, body: '{}')

    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente', enabled: true, allowed_inbox_ids: [customer_inbox.id], quote_inbox_id: email_inbox.id,
                  required_qualification_fields: [])
    ScanSolo::AiAgent::PublishService.new(account: account).call
    writer.complete!(at: Time.current)
    writer.record_next_action!(value: 'proposta', source_message_id: nil)
    perform_enqueued_jobs(only: SendReplyJob) { ScanSolo::Quote::RequestService.call(opportunity: opportunity) }
  end

  def link
    described_class.link!(
      quote_reply: ScanSolo::QuoteReply.find(quote_reply.id), quote_request: ScanSolo::QuoteRequest.find(quote_request.id), actor: admin
    )
  rescue CustomExceptions::ScanSolo::QuoteReplyRejected => e
    e.code
  end

  it 'processes two concurrent links once (RNF-02)' do
    quote_reply
    quote_request

    results = Array.new(2) { Thread.new { link } }.map(&:value)

    expect(results.count('already_linked')).to eq(1)
    expect(ScanSolo::ProposalVersion.where(quote_request: quote_request).count).to eq(1)
    expect(ScanSolo::MakeRequest.count).to eq(1)
    expect(ScanSolo::AuditEvent.where(event_type: 'quote_reply.linked').count).to eq(1)
    expect(ScanSolo::AuditEvent.where(event_type: 'quote_reply.accepted').count).to eq(1)
  end

  it 'keeps the request and its version untouched when discarding a late_reply' do
    link
    late = ScanSolo::QuoteReply.create!(account: account, message: create(:message, account: account, inbox: email_inbox,
                                                                                    conversation: quote_request.email_conversation,
                                                                                    message_type: :incoming),
                                        conversation_id: quote_request.email_conversation_id, kind: :late_reply, quote_request: quote_request)

    expect { described_class.discard!(quote_reply: late, actor: admin) }
      .not_to(change { [quote_request.reload.attributes, ScanSolo::ProposalVersion.pluck(:status)] })

    expect(late.reload).to have_attributes(status: 'discarded', resolved_by: admin)
  end
end
