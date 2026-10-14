# frozen_string_literal: true

require 'rails_helper'

# Regression: the customer answers the last 5 required fields in one message.
# The model (output shape captured from production) confirms all of them and,
# in the same answer, still asks one of them again and records
# `aguardar_cliente`. Before the fix the concluded qualification blocked that
# reply twice (`qualification_closed`, 0 messages) and, had it passed, kept
# `aguardar_cliente`, so no quote was ever requested.
RSpec.describe ScanSolo::AiTurn::TurnOrchestrator do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:email_inbox) do
    create(:channel_email, account: account, email: 'comercial@example.com', smtp_enabled: true,
                           smtp_address: 'smtp.example.com', smtp_port: 587, smtp_login: 'login', smtp_password: 'secret').inbox
  end
  let(:contact) { create(:contact, account: account, name: 'Lead Teste', email: 'lead@example.com') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
  end
  let(:writer) { ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state) }
  let(:earlier) { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact) }
  let(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact,
                     content: 'Endereço do local: https://maps.example.com/abc Lat: -8.1 Lon: -36.9 Área a ser investigada: Superfície do ' \
                              'vertedouro. Blocos do 6 ao 16 Profundidade aproximada Em torno de 1,50m Prazo: Cerca de 30dd. Integração de ' \
                              'segurança Trabalho em altura com espaço restrito e área sob vigilância')
  end
  let(:last_fields) do
    {
      'endereco_obra' => { 'value' => 'https://maps.example.com/abc (Lat -8.1, Lon -36.9)', 'status' => 'confirmado' },
      'area' => { 'value' => 'Superfície do vertedouro, blocos 6 ao 16', 'status' => 'confirmado' },
      'profundidade' => { 'value' => 'Em torno de 1,50 m', 'status' => 'confirmado' },
      'prazo_desejado' => { 'value' => 'Cerca de 30 dias', 'status' => 'confirmado' },
      'integracao_seguranca' => { 'value' => 'Trabalho em altura, espaço restrito e área sob vigilância', 'status' => 'confirmado' }
    }
  end
  let(:model_actions) do
    [
      { 'action_id' => 'qualification_field', 'params' => { 'fields' => last_fields } },
      { 'action_id' => 'cadence_signal', 'params' => { 'signal' => 'partial_reply' } },
      { 'action_id' => 'lead_state_update',
        'params' => { 'intent' => 'orcamento', 'next_action' => 'aguardar_cliente', 'interpretation_risk' => false } }
    ]
  end
  let(:model_reply) do
    'Perfeito: vertedouro blocos 6 ao 16, ~1,50 m, prazo ~30 dias. Só pra eu fechar: a entrada da equipe exige integração de ' \
      'segurança formal ou é só identificação na portaria?'
  end
  let(:provider) do
    lambda do |**kwargs|
      ScanSolo::TestMode::MockLlmProvider.call(**kwargs, fixture_response: model_reply, fixture_actions: model_actions,
                                                         fixture_asked_fields: ['integracao_seguranca'])
    end
  end
  let(:replies) { conversation.messages.outgoing.where(private: false).order(:id) }

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
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente ScanSolo', enabled: true, allowed_inbox_ids: [inbox.id], quote_inbox_id: email_inbox.id,
                  required_qualification_fields: ['Objetivo do serviço', 'Cidade / UF', 'Endereço da obra', 'Área ou extensão',
                                                  'Profundidade de interesse', 'Prazo desejado', 'Integração de segurança', 'Empresa', 'E-mail'])
    ScanSolo::AiAgent::PublishService.new(account: account).call
    { 'tipo_intervencao' => 'Investigar vazios na barragem (GPR)', 'cidade_uf' => 'Ipojuca - PE', 'empresa' => 'Consórcio Exemplo',
      'email' => 'lead@example.com' }.each do |key, value|
      writer.apply_field!(key: key, value: value, status: 'confirmado', source_message_id: earlier.id)
    end
    writer.set_intent!(intent: 'orcamento', source_message_id: earlier.id)
    writer.record_next_action!(value: 'aguardar_cliente', source_message_id: earlier.id)
  end

  def run_turn
    described_class.call(message: message, llm_provider: provider)
    ScanSolo::AiTurn.find_by!(message_id: message.id)
  end

  it 'persists the last fields, concludes once and answers with an intent, never claiming the request was sent' do
    turn = run_turn

    expect(turn).to be_succeeded
    lead_state = opportunity.lead_state.reload
    expect(lead_state.fields.slice(*last_fields.keys).transform_values { |field| field['status'] }.values.uniq).to eq(['confirmado'])
    expect(lead_state).to have_attributes(qualification_status: 'concluida', next_action: 'proposta')
    expect(opportunity.reload.stage).to eq('qualificado')
    expect(replies.sole.content).to eq(I18n.t('scan_solo.qualification.completed_reply.quote'))
    expect(ScanSolo::QuoteRequest.count).to eq(0)
    expect(ScanSolo::QuoteRequestJob).to have_been_enqueued.with(opportunity.id).once
  end

  it 'opens one quote request, sends it and only then confirms the forwarding to the lead' do
    run_turn
    perform_enqueued_jobs(only: [ScanSolo::QuoteRequestJob, SendReplyJob])

    quote_request = ScanSolo::QuoteRequest.sole
    expect(quote_request).to have_attributes(opportunity_id: opportunity.id, status: 'awaiting_reply', sent_at: be_present)
    sent = ScanSolo::AuditEvent.where(event_type: 'quote_request.sent').sole
    expect(replies.pluck(:content)).to eq([I18n.t('scan_solo.qualification.completed_reply.quote'), I18n.t('scan_solo.quote.customer_notice')])
    expect(replies.last.id).to eq(quote_request.customer_notice_message_id)
    expect(replies.last.created_at).to be >= sent.created_at
  end

  it 'requests no second quote nor message when the same message is processed again' do
    run_turn
    perform_enqueued_jobs(only: [ScanSolo::QuoteRequestJob, SendReplyJob])

    expect do
      run_turn
      perform_enqueued_jobs(only: [ScanSolo::QuoteRequestJob, SendReplyJob])
    end.to not_change(ScanSolo::QuoteRequest, :count).and(not_change { replies.count })
    expect(ScanSolo::AuditEvent.where(event_type: 'lead_state.qualification_completed').count).to eq(1)
  end
end
