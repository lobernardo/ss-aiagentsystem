# frozen_string_literal: true

require 'rails_helper'

# Escalação filtrada RF-01..RF-09, RF-12..RF-16: the 4 real cases (Daiane,
# Alexandre, Azanis, CSI) plus the qualified-without-quote and negotiation
# variants, end to end through real turns. Every turn runs the real
# ScanSolo::AiTurn::TurnOrchestrator with ScanSolo::TestMode::MockLlmProvider
# and WebMock blocking any real HTTP; the published config carries the
# fictitious number +5511999999999 and the commercial notice goes through the
# real ScanSolo::Notifications::Publisher with the e-mail adapter stubbed.
# Every turn is checked for RF-14 (1 outgoing message, only "Artur", only the
# published number) by `single_reply_after`.
RSpec.describe 'ScanSolo escalação filtrada' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:contact) { create(:contact, account: account, name: 'Ana', email: nil, phone_number: nil, custom_attributes: {}) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, assignee: agent) }
  let(:stage) { :em_contato }
  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: stage)
  end
  let(:published_number) { '+5511999999999' }
  let(:email) { 'vendas@example.com' }
  let(:config) { ScanSolo::AiAgentConfig.published_for(account) }
  let(:published_link) { ScanSolo::Commercial::WhatsappLink.build(config: config, opportunity: opportunity) }
  let(:placeholder) { ScanSolo::Commercial::WhatsappLink::PLACEHOLDER }
  let(:payloads) { [] }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    allow(ScanSolo::Notifications::EmailAdapter).to receive(:call)
      .and_return(ScanSolo::Notifications::Publisher::Result.new(success: true, reason: nil))
    allow(ScanSolo::Notifications::Publisher).to receive(:call).and_call_original
    allow(ScanSolo::Knowledge::EmbeddingService).to receive(:call) do |content:, **|
      ScanSolo::TestMode::MockEmbeddingProvider.call(content: content)
    end
    ScanSolo::AiAgentConfig.draft_for!(account).update!(
      name: 'Agente ScanSolo', enabled: true, allowed_inbox_ids: [inbox.id], commercial_whatsapp_number: published_number,
      quote_recipient_email: email, required_qualification_fields: ['Profundidade de investigação', 'Prazo desejado']
    )
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  # One MockLlmProvider response per model call, in order (the last one
  # repeats). Returns the turn and its single reply, checked for RF-14.
  def run_turn(content, *responses)
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact,
                               content: content)
    provider = lambda do |**kwargs|
      payloads << kwargs[:payload]
      ScanSolo::TestMode::MockLlmProvider.call(**kwargs, **responses.fetch([payloads.size, responses.size].min - 1, {}))
    end
    ScanSolo::AiTurn::TurnOrchestrator.call(message: message, llm_provider: provider)

    [ScanSolo::AiTurn.find_by!(message_id: message.id), single_reply_after(message)]
  end

  # RF-14: exactly 1 outgoing message, no internal name in it nor in the
  # system message, no phone besides the published one.
  def single_reply_after(message)
    reply = conversation.messages.outgoing.where(private: false).where('messages.id > ?', message.id).sole.content
    expect([reply, payloads.last[:system].to_s].map { |text| ScanSolo::Commercial::Rules.internal_name?(text) }).to eq([false, false])
    expect(reply.gsub(published_link, '').scan(/\d[\d\s().-]{7,}\d/)).to be_empty
    reply
  end

  def escalation(reason, reply = "Fale com o Artur pelo WhatsApp: #{placeholder}")
    { fixture_response: reply, fixture_actions: [{ 'action_id' => 'escalate_to_commercial', 'params' => { 'reason' => reason } }] }
  end

  def negotiation
    { fixture_response: 'Consigo fazer 10% de desconto à vista.',
      fixture_actions: [{ 'action_id' => 'lead_state_update', 'params' => { 'negotiation_requested' => true } }] }
  end

  def events(event_type, correlation_id: nil)
    scope = ScanSolo::AuditEvent.where(subject: opportunity, event_type: event_type)
    correlation_id ? scope.where(correlation_id: correlation_id) : scope
  end

  def commercial_status
    opportunity.reload
    ScanSolo::Reports::CommercialStatus.call(quote_request: opportunity.quote_request, current_version: opportunity.proposal&.current_version,
                                             escalated: opportunity.escalated_to_commercial?)
  end

  def email_first(key, **)
    I18n.t("scan_solo.commercial.email_first.#{key}", email: email, **)
  end

  def send_quote_request!
    ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid, sent_at: 1.day.ago)
  end

  def expect_redirected_without_link(reply)
    expect(reply).to include(email)
    expect(reply).not_to include('wa.me/', 'api.whatsapp.com', '{{')
    expect(opportunity.reload).to have_attributes(escalated_to_commercial_at: nil, escalation_reason: nil, email_redirect_count: 0)
    expect(events('commercial.escalated')).to be_none
  end

  describe 'Daiane: em_contato asking the rental price (RF-01, RF-12, RF-16)' do
    it 'replies with the e-mail, writes no mark, keeps the counter and publishes nothing' do
      _turn, reply = run_turn('Qual o valor da locação do equipamento?', escalation('assunto_orcamento'))

      expect_redirected_without_link(reply)
      expect(ScanSolo::Notifications::Publisher).not_to have_received(:call)
      expect(commercial_status).to eq('nao_encaminhado')
    end

    it 'sends 0 messages with wa.me/ when the model writes the published link literally (RF-09)' do
      # The reply carries the e-mail and asks an eligible field, so it is kept and reaches the validator.
      literal = escalation('assunto_orcamento', "Escreva para #{email} ou chame #{published_link}. Qual a profundidade?")
                .merge(fixture_asked_fields: ['profundidade'])

      turn, reply = run_turn('Qual o valor da locação?', literal)

      expect(payloads.size).to eq(2)
      expect(turn.context_snapshot['output_fallback']).to eq('violation' => 'commercial_link_not_allowed')
      expect(conversation.messages.where('content LIKE ?', '%wa.me/%')).to be_none
      expect(reply).not_to include('wa.me/')
      expect(opportunity.reload).to have_attributes(escalated_to_commercial_at: nil, email_redirect_count: 0)
      expect(ScanSolo::Notifications::Publisher).not_to have_received(:call)
    end
  end

  context 'when the lead is em_qualificacao' do
    let(:stage) { :em_qualificacao }
    let(:missing) { %w[profundidade prazo_desejado] }

    before do
      fields = (ScanSolo::Qualification::FieldResolver::CATALOG_KEYS - missing).index_with do |key|
        { 'value' => "valor #{key}", 'status' => 'confirmado' }
      end
      opportunity.lead_state.update!(fields: fields)
    end

    describe 'Alexandre: missing profundidade and prazo, asking the approximate cost (RF-01, RF-02, RF-15, RF-16)' do
      it 'replies with the e-mail, resumes the qualification asking only missing fields and keeps the cadence going' do
        turn, reply = run_turn('Qual o custo aproximado?', escalation('assunto_orcamento'))

        asked = turn.reload.context_snapshot['asked_fields']
        expect(asked).to be_present
        expect(asked - missing).to be_empty
        expect(turn.context_snapshot).not_to include('output_fallback', 'output_regeneration')
        expect_redirected_without_link(reply)
        expect(ScanSolo::Notifications::Publisher).not_to have_received(:call)
        expect(commercial_status).to eq('nao_encaminhado')

        definition = ScanSolo::CadenceDefinition.create!(stage: 'em_qualificacao', version: 1, offsets: [24])
        attempt = ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: definition).attempts.sole
        expect(ScanSolo::Cadence::AttemptPrecheck.call(attempt: attempt).reason).not_to eq('commercial_escalated')
      end
    end

    describe 'Azanis: each escalation reason and a negotiation (RF-01, RF-12, RF-16)' do
      it 'redirects every request by e-mail with 0 marks, 0 escalations and the counter unchanged' do
        requests = ScanSolo::PipelineOpportunity::ESCALATION_REASONS.map { |reason| escalation(reason) } + [negotiation]

        requests.each do |response|
          _turn, reply = run_turn('Qual a previsão da cotação?', response)

          expect_redirected_without_link(reply)
        end
        expect(ScanSolo::Notifications::Publisher).not_to have_received(:call)
        expect(opportunity.reload.stage).to eq('em_qualificacao')
        expect(commercial_status).to eq('nao_encaminhado')
      end
    end
  end

  context 'when the lead is qualificado without a quote request sent (RF-03)' do
    let(:stage) { :qualificado }

    it 'replies quote_pending with no mark, no link and the counter unchanged' do
      _turn, reply = run_turn('Qual o prazo de execução?', escalation('assunto_orcamento'))

      expect(reply).to eq(email_first(:quote_pending))
      expect_redirected_without_link(reply)
      expect(ScanSolo::Notifications::Publisher).not_to have_received(:call)
    end
  end

  describe 'CSI: qualificado with the quote request sent (RF-04..RF-08, RF-12, RF-16)' do
    let(:stage) { :qualificado }

    before { send_quote_request! }

    it 'redirects the 1st request by e-mail, counting 1, with no link and no notice (RF-04)' do
      _turn, reply = run_turn('Qual o prazo da entrega?', escalation('assunto_orcamento'))

      expect(reply).to eq(email_first(:quote_sent))
      expect(reply).not_to include('wa.me/')
      expect(opportunity.reload).to have_attributes(email_redirect_count: 1, escalated_to_commercial_at: nil)
      expect(ScanSolo::Notifications::Publisher).not_to have_received(:call)
      expect(commercial_status).to eq('aguardando_artur')
    end

    context 'when the 1st request was redirected' do
      before { run_turn('Qual o prazo da entrega?', escalation('assunto_orcamento')) }

      it 'escalates the 2nd request with 1 escalation, 1 notice and exactly 1 link (RF-05, RF-12, RF-16)' do
        turn, reply = run_turn('Preciso do prazo ainda hoje.', escalation('assunto_orcamento'))

        expect(opportunity.reload).to have_attributes(escalation_reason: 'assunto_orcamento', escalated_to_commercial_at: be_present)
        expect(events('commercial.escalated', correlation_id: turn.correlation_id).count).to eq(1)
        expect(ScanSolo::Notifications::Publisher).to have_received(:call).with(hash_including(event: 'commercial.escalated')).once
        expect(reply.scan('wa.me/').size).to eq(1)
        expect(reply.scan('https://wa.me/5511999999999').size).to eq(1)
        expect(commercial_status).to eq('escalado_wa')
      end
    end

    context 'when the link was already sent' do
      before do
        run_turn('Qual o prazo da entrega?', escalation('assunto_orcamento'))
        run_turn('Preciso do prazo ainda hoje.', escalation('assunto_orcamento'))
      end

      it 'answers "Ok" and "obrigado" without the link and with 0 new events (RF-06, RF-07)' do
        escalated_at = opportunity.reload.escalated_to_commercial_at

        [['Ok', "Combinado! #{placeholder}"], ['obrigado', 'Por nada!']].each do |content, response|
          reply = nil
          expect { reply = run_turn(content, { fixture_response: response }).last }
            .not_to(change { ScanSolo::AuditEvent.where(subject: opportunity).count })
          expect(reply).not_to include('wa.me/', '{{')
        end
        expect(opportunity.reload.escalated_to_commercial_at).to eq(escalated_at)
        expect(ScanSolo::ConversationExtension.resolve_for(conversation)).to be_ai_active
      end

      it 'treats an explicit request as a real escalation: overwritten mark, 1 audit, 1 link, 0 new notices (RF-08, RF-12)' do
        escalated_at = opportunity.reload.escalated_to_commercial_at

        turn, reply = travel_to(1.hour.from_now) { run_turn('Me passa o contato do comercial de novo?', escalation('pedido_humano')) }

        expect(opportunity.reload).to have_attributes(escalation_reason: 'pedido_humano', escalated_to_commercial_at: be > escalated_at)
        expect(events('commercial.escalated', correlation_id: turn.correlation_id).count).to eq(1)
        expect(reply.scan('wa.me/').size).to eq(1)
        expect(ScanSolo::Notifications::Publisher).to have_received(:call).once
        expect(commercial_status).to eq('escalado_wa')
      end
    end
  end

  context 'when the lead is proposta_enviada and asks for a negotiation (RF-13)' do
    let(:stage) { :proposta_enviada }

    def stage_events
      ScanSolo::PipelineStageEvent.where(opportunity: opportunity)
    end

    it 'with the quote request sent, moves to negociacao and redirects by e-mail, counting 1' do
      send_quote_request!

      turn, reply = run_turn('Consegue um desconto à vista?', negotiation)

      expect(stage_events.sole).to have_attributes(from_stage: 'proposta_enviada', to_stage: 'negociacao')
      expect(events('negotiation.requested', correlation_id: turn.correlation_id).count).to eq(1)
      expect(opportunity.reload).to have_attributes(stage: 'negociacao', escalated_to_commercial_at: nil, email_redirect_count: 1)
      expect(reply).to eq(email_first(:quote_sent))
      expect(ScanSolo::Notifications::Publisher).not_to have_received(:call)
    end

    it 'without the quote request sent, moves to negociacao and keeps the counter at 0' do
      turn, reply = run_turn('Consegue um desconto à vista?', negotiation)

      expect(stage_events.sole).to have_attributes(from_stage: 'proposta_enviada', to_stage: 'negociacao')
      expect(events('negotiation.requested', correlation_id: turn.correlation_id).count).to eq(1)
      expect(opportunity.reload).to have_attributes(stage: 'negociacao', escalated_to_commercial_at: nil, email_redirect_count: 0)
      expect(reply).to include(email)
      expect(reply).not_to include('wa.me/', '10%')
      expect(ScanSolo::Notifications::Publisher).not_to have_received(:call)
    end
  end
end
