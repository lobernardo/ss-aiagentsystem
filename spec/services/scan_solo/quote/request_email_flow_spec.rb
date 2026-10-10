# frozen_string_literal: true

require 'rails_helper'

# RNF-08 end to end: qualification completion → QuoteRequestJob → CT-01 e-mail
# delivered by the native mailer → update window → CT-03 update e-mail, plus
# the reply read by the unchanged OC/CT-04 parser. RNF-07: ActionMailer :test,
# WebMock with no request made, no LLM; nothing is really sent.
RSpec.describe 'Quote request e-mail flow (scansolo-solicitacao-orcamento-email)' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:customer_inbox) { create(:inbox, account: account) }
  let(:email_inbox) do
    channel = create(:channel_email, account: account, email: 'atendimento.comercial@scansolo.com.br', smtp_enabled: true,
                                     smtp_address: 'smtp.example.com', smtp_port: 587, smtp_login: 'login', smtp_password: 'secret')
    channel.inbox.tap { |inbox| inbox.update!(business_name: 'Atendimento Comercial ScanSolo', sender_name_type: :professional) }
  end
  let(:contact) { create(:contact, account: account, name: 'Ana Souza', email: 'ana@amaggi.example', phone_number: nil) }
  let(:conversation) { create(:conversation, account: account, inbox: customer_inbox, contact: contact) }
  let(:opportunity) { ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao) }
  let(:writer) { ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state) }
  let(:empresa) { 'AMAGGI Exportação e Importação Ltda.' }
  let(:validation_mode) { true }
  let(:validation_paragraph) do
    'Nesse primeiro momento estou aprendendo como automatizar a construção deste template, ' \
      'então você pode olhar como está ficando para irmos validando.'
  end
  let(:start) { Time.zone.local(2026, 10, 10, 9, 0, 0) }
  let(:quote_request) { ScanSolo::QuoteRequest.find_by!(opportunity: opportunity) }
  let(:thread_messages) { quote_request.email_conversation.messages }
  let(:update_messages) { thread_messages.where("additional_attributes ->> 'scansolo_origin' = 'quote_request_update'") }

  around do |example|
    original = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :test
    example.run
  ensure
    ActionMailer::Base.delivery_method = original
  end

  before do
    allow_any_instance_of(ConversationReplyMailer).to receive(:set_delivery_method) # rubocop:disable RSpec/AnyInstance
    allow(ScanSolo::AiTurn::ModelInvoker).to receive(:call).and_raise('LLM must not be called (RF-01)')
    allow(RubyLLM).to receive(:context).and_raise('LLM must not be called (RF-01)')
    ActionMailer::Base.deliveries.clear
    ScanSolo::AiAgentConfig.draft_for!(account).update!(
      name: 'Agente', enabled: true, allowed_inbox_ids: [customer_inbox.id], quote_inbox_id: email_inbox.id,
      required_qualification_fields: ['Empresa / razão social'], quote_email_validation_mode: validation_mode
    )
    ScanSolo::AiAgent::PublishService.new(account: account).call

    lead_message = create(:message, account: account, conversation: conversation, message_type: :incoming)
    writer.set_intent!(intent: 'orcamento', source_message_id: lead_message.id)
    { 'empresa' => empresa, 'cidade_uf' => 'Lucas do Rio Verde/MT', 'tecnologia' => 'GPR',
      'endereco_obra' => 'Rodovia BR-163, km 690', 'tipo_intervencao' => 'Localizar tubulações antes da escavação' }.each do |key, value|
      writer.apply_field!(key: key, value: value, status: 'confirmado', source_message_id: lead_message.id)
    end
  end

  def conclude!
    turn_message = create(:message, account: account, conversation: conversation, message_type: :incoming)
    turn = ScanSolo::AiTurn.create!(message: turn_message, conversation: conversation, correlation_id: SecureRandom.uuid)
    perform_enqueued_jobs(only: [ScanSolo::QuoteRequestJob, SendReplyJob]) do
      ScanSolo::LeadState::CompletionService.call(opportunity: ScanSolo::PipelineOpportunity.find(opportunity.id), turn: turn)
    end
  end

  def change_field!(key, value, at:)
    travel_to(at) { writer.apply_field!(key: key, value: value, status: 'confirmado', source_message_id: nil) }
  end

  def run_update_window!(at:)
    travel_to(at) do
      perform_enqueued_jobs(only: ScanSolo::QuoteRequestUpdateJob, at: Time.current)
      perform_enqueued_jobs(only: SendReplyJob)
    end
  end

  def html_of(mail)
    (mail.html_part || mail).body.decoded
  end

  describe 'request e-mail on completion (RF-01, RF-15, CT-01)' do
    it 'delivers the AMAGGI e-mail from the quote inbox display name with no new Reply-To' do
      travel_to(start) { conclude! }

      mail = ActionMailer::Base.deliveries.sole
      expect(mail[:from].value).to eq('Atendimento Comercial ScanSolo <atendimento.comercial@scansolo.com.br>')
      expect(mail.to).to eq(['comercial@scansolo.com.br'])
      expect(mail.subject).to eq('Solicitação de orçamento | AMAGGI | GeoRadar | Lucas do Rio Verde/MT')
      # Native Reply-To of an e-mail inbox, unchanged by this feature.
      expect(mail.reply_to).to eq(["reply+#{quote_request.email_conversation.uuid}@#{account.inbound_email_domain}"])
      expect(html_of(mail)).to include('Telefone/WhatsApp do solicitante: não informado', 'Cidade/UF: Lucas do Rio Verde/MT')
      expect(a_request(:any, /.*/)).not_to have_been_made
      expect(ScanSolo::AiTurn::ModelInvoker).not_to have_received(:call)
    end
  end

  describe 'malicious company value (RF-17)' do
    let(:empresa) { "<script>x</script>\r\nBcc: a@b.c" }

    it 'delivers the e-mail with the value escaped, a single-line subject and no Bcc header' do
      conclude!

      mail = ActionMailer::Base.deliveries.sole
      expect(mail.bcc).to be_nil
      expect(mail.header['Bcc']).to be_nil
      expect(mail.to).to eq(['comercial@scansolo.com.br'])
      expect(mail.subject).not_to match(/[\r\n]/)
      expect(html_of(mail)).to include('&lt;script&gt;')
      expect(html_of(mail)).not_to include('<script>')
    end
  end

  describe 'Luciano reply (RF-11, OC/CT-04)' do
    it 'reads the filled block written above the quoted new e-mail as today' do
      conclude!
      quoted = thread_messages.sole.content.gsub("\n", "\n> ")
      reply = create(:message, account: account, inbox: email_inbox, conversation: quote_request.email_conversation, message_type: :incoming,
                               sender: quote_request.email_conversation.contact, content: <<~TEXT)
                                 Segue o orçamento.

                                 === RESPOSTA DO ORÇAMENTO ===
                                 Valor total: R$ 12.500,00
                                 Prazo/cronograma: 30 dias
                                 Escopo/atividades: Varredura GPR
                                 Condições de pagamento: 50% na assinatura
                                 Observações comerciais:
                                 === FIM ===

                                 Em 10/10/2026 09:00, Atendimento Comercial ScanSolo escreveu:
                                 > #{quoted}
                               TEXT

      perform_enqueued_jobs(only: SendReplyJob) { ScanSolo::Quote::ReplyProcessor.call(message: reply) }

      expect(quote_request.reload).to have_attributes(status: 'replied', reply_message_id: reply.id)
      expect(quote_request.commercial).to include('schedule' => '30 dias', 'scope' => 'Varredura GPR', 'payment_terms' => '50% na assinatura')
      expect(BigDecimal(quote_request.commercial['total_value'])).to eq(BigDecimal('12500.00'))
    end
  end

  describe 'update e-mail in the fixed window (RF-14, CT-03)' do
    before { travel_to(start) { conclude! } }

    it 'sends 1 update with the 3 changes made in 2 minutes, at the end of the window' do
      change_field!('profundidade', '3 m', at: start + 1.minute)
      change_field!('area', '500 m²', at: start + 2.minutes)
      change_field!('prazo_desejado', '15 dias', at: start + 3.minutes)

      update_jobs = enqueued_jobs.select { |job| job[:job] == ScanSolo::QuoteRequestUpdateJob }
      expect(update_jobs.sole[:at]).to eq((start + 11.minutes).to_f)

      ActionMailer::Base.deliveries.clear
      run_update_window!(at: start + 11.minutes)

      body = update_messages.sole.content
      expect(body.lines.first.chomp).to eq('Atualização:')
      expect(body).to include('Profundidade de interesse: não informado → 3 m', 'Área/extensão: não informado → 500 m²',
                              'Prazo desejado: não informado → 15 dias', 'DADOS DO CLIENTE')
      expect(body).to end_with(ScanSolo::Quote::EmailComposer.empty_block)
      mail = ActionMailer::Base.deliveries.sole
      expect(mail.subject).to eq("Re: #{quote_request.email_conversation.additional_attributes['mail_subject']}")
      expect(quote_request.reload).to be_awaiting_reply
    end

    it 'sends no update when the request is replied at the end of the window' do
      change_field!('profundidade', '3 m', at: start + 1.minute)
      quote_request.update!(status: :replied)

      run_update_window!(at: start + 11.minutes)

      expect(update_messages).to be_empty
      expect(ScanSolo::AuditEvent.where(event_type: 'quote_request.update_sent')).to be_empty
    end

    it 'records 1 quote_request.sent and 1 quote_request.update_sent by correlation id with the 5 fields (RF-19)' do
      change_field!('profundidade', '3 m', at: start + 1.minute)
      run_update_window!(at: start + 11.minutes)

      events = ScanSolo::AuditEvent.where(correlation_id: quote_request.correlation_id, event_type: %w[quote_request.sent quote_request.update_sent])
      expect(events.pluck(:event_type)).to contain_exactly('quote_request.sent', 'quote_request.update_sent')
      expected_messages = { 'quote_request.sent' => quote_request.request_message_id, 'quote_request.update_sent' => update_messages.sole.id }
      events.each do |event|
        expect(event.payload).to include(
          'opportunity_id' => opportunity.id, 'template_version' => 'quote_request_email.v2', 'recipient' => 'comercial@scansolo.com.br',
          'message_id' => expected_messages.fetch(event.event_type), 'result' => 'sent'
        )
      end
    end
  end

  describe 'validation mode (RF-12, RF-21)' do
    let(:validation_mode) { false }

    it 'has 0 validation paragraphs once turned off and published' do
      conclude!

      expect(thread_messages.sole.content).not_to include(validation_paragraph)
      expect(html_of(ActionMailer::Base.deliveries.sole)).not_to include('Nesse primeiro momento')
    end

    it 'keeps the published value while the draft is turned back on' do
      ScanSolo::AiAgentConfig.draft_for!(account).update!(quote_email_validation_mode: true)

      conclude!

      expect(thread_messages.sole.content).not_to include(validation_paragraph)
    end
  end

  it 'has 1 validation paragraph while the published mode is on (RF-12)' do
    conclude!

    expect(thread_messages.sole.content.scan(validation_paragraph).size).to eq(1)
  end
end
