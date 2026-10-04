# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Quote::ReplyProcessor do
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
  let(:quote_request) { ScanSolo::QuoteRequest.find_by!(opportunity: opportunity) }
  let(:email_conversation) { quote_request.email_conversation }
  let(:scenario_url) { 'https://hook.make.example/scenario-webhook' }
  let(:http_inside_transaction) { [] }
  let(:valid_block) do
    <<~TEXT
      Segue o orçamento.

      === RESPOSTA DO ORÇAMENTO ===
      Valor total: R$ 12.500,00
      Prazo/cronograma: 30 dias
      Escopo/atividades: Sondagem SPT
      Condições de pagamento: 50% na assinatura
      Observações comerciais:
      === FIM ===

      Em 01/10/2026 10:00, Atendimento escreveu:
      > #{ScanSolo::Quote::EmailComposer.empty_block.gsub("\n", "\n> ")}
    TEXT
  end
  let(:block_without_payment) { valid_block.sub("Condições de pagamento: 50% na assinatura\n", '') }

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
    stub_request(:post, scenario_url).to_return do
      http_inside_transaction << ActiveRecord::Base.connection.current_transaction.joinable?
      { status: 200, body: '{}' }
    end
    allow(ScanSolo::AiTurn::ModelInvoker).to receive(:call).and_raise('LLM must not be called (RF-21)')
    allow(RubyLLM).to receive(:context).and_raise('LLM must not be called (RF-21)')

    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente', enabled: true, allowed_inbox_ids: [customer_inbox.id], quote_inbox_id: email_inbox.id,
                  required_qualification_fields: [])
    ScanSolo::AiAgent::PublishService.new(account: account).call
    writer.complete!(at: Time.current)
    writer.record_next_action!(value: 'proposta', source_message_id: nil)
    perform_enqueued_jobs(only: SendReplyJob) { ScanSolo::Quote::RequestService.call(opportunity: opportunity) }
  end

  def reply(content, in_conversation: email_conversation)
    create(:message, account: account, inbox: email_inbox, conversation: in_conversation, message_type: :incoming,
                     sender: in_conversation.contact, content: content)
  end

  def process(message)
    perform_enqueued_jobs(only: SendReplyJob) { described_class.call(message: message) }
  end

  describe 'valid block (RF-17, RF-24)' do
    it 'marks the request replied and requests one generation with the commercial data only after commit' do
      message = reply(valid_block)

      process(message)

      expect(quote_request.reload).to have_attributes(status: 'replied', reply_message_id: message.id, replied_at: be_present)
      expect(quote_request.commercial).to include('schedule' => '30 dias', 'scope' => 'Sondagem SPT', 'payment_terms' => '50% na assinatura')
      expect(BigDecimal(quote_request.commercial['total_value'])).to eq(BigDecimal('12500.00'))
      expect(ScanSolo::ProposalVersion.where(quote_request: quote_request).sole).to be_generating
      make_request = ScanSolo::MakeRequest.sole
      expect(make_request.payload.dig('commercial', 'total_value')).to eq(12_500.0)
      expect(http_inside_transaction).to eq([false])
    end

    it 'never calls an LLM (RF-21)' do
      process(reply(valid_block))

      expect(ScanSolo::AiTurn::ModelInvoker).not_to have_received(:call)
      expect(RubyLLM).not_to have_received(:context)
    end

    it 'keeps the chain navigable from the opportunity with one correlation id (RF-22, RNF-09)' do
      message = reply(valid_block)
      process(message)

      request = ScanSolo::PipelineOpportunity.find(opportunity.id).quote_request
      version = request.proposal_version
      expect(request.email_conversation.messages.incoming.sole).to eq(message)
      expect(request.reply_message).to eq(message)
      expect(ScanSolo::MakeRequest.find_by!(correlation_id: version.generate_correlation_id).action).to eq('proposal.generate')
      expect(ScanSolo::AuditEvent.where(correlation_id: request.correlation_id, subject: opportunity).pluck(:event_type))
        .to contain_exactly('quote_request.sent', 'quote_reply.accepted', 'proposal.generation_requested')
      expect(ScanSolo::AuditEvent.find_by!(event_type: 'proposal.generation_requested').payload)
        .to include('generate_correlation_id' => version.generate_correlation_id, 'proposal_version_id' => version.id)
    end

    it 'records the rejected generation without raising when the proposal gate fails' do
      ScanSolo::AiAgentConfig.draft_for!(account).update!(required_qualification_fields: ['Área'])
      ScanSolo::AiAgent::PublishService.new(account: account).call
      allow(ChatwootExceptionTracker).to receive(:new).and_call_original

      expect { process(reply(valid_block)) }.not_to raise_error

      expect(quote_request.reload).to be_replied
      expect(ScanSolo::ProposalVersion.count).to eq(0)
      expect(ScanSolo::AuditEvent.where(event_type: 'proposal.generation_rejected').sole.correlation_id).to eq(quote_request.correlation_id)
      expect(ChatwootExceptionTracker).to have_received(:new).with(an_instance_of(ActiveRecord::RecordInvalid), account: account)
    end
  end

  describe 'invalid block (RF-18)' do
    it 'asks for a correction in the request thread and creates no version' do
      process(reply(block_without_payment))

      expect(quote_request.reload).to be_correction_requested
      expect(ScanSolo::ProposalVersion.count).to eq(0)
      expect(ScanSolo::MakeRequest.count).to eq(0)
      correction = email_conversation.messages.outgoing.order(:id).last
      expect(correction.id).not_to eq(quote_request.request_message_id)
      expect(correction.content).to include('Condições de pagamento', ScanSolo::Quote::EmailComposer.empty_block)
      expect(ScanSolo::AuditEvent.find_by!(event_type: 'quote_reply.rejected'))
        .to have_attributes(correlation_id: quote_request.correlation_id, payload: include('problems' => ['payment_terms']))
    end

    it 'treats a dot-decimal value as illegible, then generates on a later valid reply' do
      process(reply(valid_block.sub('R$ 12.500,00', '12500.00')))

      expect(quote_request.reload).to be_correction_requested
      expect(ScanSolo::ProposalVersion.count).to eq(0)

      process(reply(valid_block))

      expect(quote_request.reload).to be_replied
      expect(ScanSolo::ProposalVersion.where(quote_request: quote_request).count).to eq(1)
    end
  end

  describe 'pending replies (RF-19, RF-23)' do
    it 'records an e-mail without a known thread as one unmatched pending' do
      other = create(:conversation, account: account, inbox: email_inbox)

      process(reply(valid_block, in_conversation: other))

      expect(ScanSolo::QuoteReply.sole).to have_attributes(kind: 'unmatched', status: 'pending', quote_request_id: nil)
      expect(ScanSolo::ProposalVersion.count).to eq(0)
      expect(ScanSolo::AuditEvent.where(event_type: 'quote_reply.pending').count).to eq(1)
    end

    it 'records a single pending for the same message processed twice' do
      message = reply('Olá', in_conversation: create(:conversation, account: account, inbox: email_inbox))

      2.times { process(message) }

      expect(ScanSolo::QuoteReply.count).to eq(1)
    end

    %w[generating sent].each do |version_status|
      it "turns a new valid reply to a replied request with a #{version_status} version into a late_reply pending" do
        process(reply(valid_block))
        version = ScanSolo::ProposalVersion.sole
        version.update_columns(status: ScanSolo::ProposalVersion.statuses.fetch(version_status)) # rubocop:disable Rails/SkipsModelValidations

        expect { process(reply(valid_block)) }.not_to(change { conversation.messages.count })

        expect(ScanSolo::QuoteReply.sole).to have_attributes(kind: 'late_reply', quote_request_id: quote_request.id)
        expect(ScanSolo::ProposalVersion.count).to eq(1)
        expect(ScanSolo::MakeRequest.count).to eq(1)
        expect(version.reload.status).to eq(version_status)
        expect(ScanSolo::AuditEvent.find_by!(event_type: 'quote_reply.pending').correlation_id).to eq(quote_request.correlation_id)
      end
    end
  end

  it 'ignores a reply to a negotiation notification (RF-42)' do
    notification = ScanSolo::Quote::EmailThread.open!(inbox: email_inbox, recipient: 'comercial@scansolo.com.br',
                                                      subject: 'Pedido de negociação', marker: 'negotiation_notification')

    expect { process(reply(valid_block, in_conversation: notification)) }.not_to(change { quote_request.reload.attributes })

    expect(ScanSolo::QuoteReply.count).to eq(0)
    expect(ScanSolo::ProposalVersion.count).to eq(0)
  end
end
