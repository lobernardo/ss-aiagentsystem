# frozen_string_literal: true

require 'rails_helper'

# Escalação comercial RF-06..RF-08, RF-10..RF-15, RF-18, RF-19, RF-23,
# RNF-04: end-to-end commercial escalation through real turns. Every turn
# runs the real ScanSolo::AiTurn::TurnOrchestrator with
# ScanSolo::TestMode::MockLlmProvider and WebMock blocking any real HTTP;
# the published config carries the fictitious number +5511999999999. The
# commercial notice goes through the real ScanSolo::Notifications::Publisher
# with the e-mail adapter stubbed.
RSpec.describe 'ScanSolo escalação comercial wa.me' do # rubocop:disable RSpec/DescribeClass
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
  let(:published_link) { 'https://wa.me/5511999999999?text=' }
  let(:placeholder) { ScanSolo::Commercial::WhatsappLink::PLACEHOLDER }
  let(:payloads) { [] }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    allow(ScanSolo::Notifications::EmailAdapter).to receive(:call)
      .and_return(ScanSolo::Notifications::Publisher::Result.new(success: true, reason: nil))
    allow(ScanSolo::Knowledge::EmbeddingService).to receive(:call) do |content:, **|
      ScanSolo::TestMode::MockEmbeddingProvider.call(content: content)
    end
    publish!(name: 'Agente ScanSolo', enabled: true, allowed_inbox_ids: [inbox.id], commercial_whatsapp_number: published_number,
             quote_recipient_email: 'vendas@example.com')
  end

  def publish!(**attributes)
    ScanSolo::AiAgentConfig.draft_for!(account).update!(attributes)
    ScanSolo::AiAgent::PublishService.new(account: account).call
  end

  def create_message(content)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact, content: content)
  end

  # One MockLlmProvider response per model call, in order (the last one
  # repeats); every payload the provider receives is kept in `payloads`.
  def run_turn(message, *responses)
    provider = lambda do |**kwargs|
      payloads << kwargs[:payload]
      ScanSolo::TestMode::MockLlmProvider.call(**kwargs, **responses.fetch([payloads.size, responses.size].min - 1, {}))
    end
    ScanSolo::AiTurn::TurnOrchestrator.call(message: message, llm_provider: provider)
    ScanSolo::AiTurn.find_by!(message_id: message.id)
  end

  def escalation(reason, reply = "Fale com o Artur pelo WhatsApp: #{placeholder}")
    { fixture_response: reply, fixture_actions: [{ 'action_id' => 'escalate_to_commercial', 'params' => { 'reason' => reason } }] }
  end

  def negotiation
    { fixture_response: 'Consigo fazer 10% de desconto à vista.',
      fixture_actions: [{ 'action_id' => 'lead_state_update', 'params' => { 'negotiation_requested' => true } }] }
  end

  def ai_replies
    conversation.messages.outgoing.where(private: false)
  end

  def private_notes
    conversation.messages.where(private: true)
  end

  def events(event_type, correlation_id: nil)
    scope = ScanSolo::AuditEvent.where(subject: opportunity, event_type: event_type)
    correlation_id ? scope.where(correlation_id: correlation_id) : scope
  end

  def extension
    ScanSolo::ConversationExtension.resolve_for(conversation)
  end

  describe '(a) the 4 triggers on an opportunity not escalated before (RF-06, RF-12, RF-23, RNF-04)' do
    {
      'duvida_proposta' => [:qualificado, 'Não entendi o escopo da proposta, pode explicar?'],
      'assunto_orcamento' => [:em_qualificacao, 'Quanto fica o orçamento para 800 m²?'],
      'duvida_sem_resposta' => [:em_contato, 'Vocês fazem laudo para o corpo de bombeiros?'],
      'pedido_humano' => [:em_contato, 'Quero falar com uma pessoa, por favor.']
    }.each do |reason, (trigger_stage, question)|
      context "with #{reason} in #{trigger_stage}" do
        let(:stage) { trigger_stage }

        it 'sends 1 reply with the link, writes 1 mark, keeps the AI active and sends 1 commercial notice' do
          turn = run_turn(create_message(question), escalation(reason))

          expect([turn.invocation_status, payloads.size]).to eq(['succeeded', 1])
          expect(ai_replies.sole.content.scan(published_link).size).to eq(1)
          expect(ai_replies.sole.content).not_to include('{{')
          expect(opportunity.reload).to have_attributes(escalation_reason: reason, escalated_to_commercial_at: be_present)
          expect(events('commercial.escalated').sole.correlation_id).to eq(turn.correlation_id)
          expect(extension).to be_ai_active
          expect(events('negotiation.notification_sent').sole.correlation_id).to eq(turn.correlation_id)
        end
      end
    end

    context 'with duvida_sem_resposta and an empty knowledge base' do
      it 'places no knowledge chunk in the turn' do
        turn = run_turn(create_message('Vocês fazem laudo para o corpo de bombeiros?'), escalation('duvida_sem_resposta'))

        expect(turn.knowledge_evidence).to be_empty
        expect(opportunity.reload.escalation_reason).to eq('duvida_sem_resposta')
      end
    end
  end

  it '(b) answers a later question covered by the knowledge base after the escalation, with 0 handoff notes (RF-10)' do
    run_turn(create_message('Quero falar com uma pessoa'), escalation('pedido_humano'))
    source = ScanSolo::KnowledgeSource.create!(account: account, added_by: agent, source_type: :faq, origin: 'manual',
                                               title: 'Horário', content: 'Qual o horário de atendimento? Das 8h às 18h.')
    ScanSolo::Knowledge::IngestionService.call(source: source, embedding_provider: ScanSolo::TestMode::MockEmbeddingProvider)

    turn = run_turn(create_message('Qual o horário de atendimento?'), { fixture_response: 'Atendemos das 8h às 18h.' })

    expect(turn).to be_succeeded
    expect(turn.knowledge_evidence).to include(hash_including('source_id' => source.id))
    expect(ai_replies.order(:id).last.content).to eq('Atendemos das 8h às 18h.')
    expect(ai_replies.where('messages.id > ?', turn.message_id).count).to eq(1)
    expect(private_notes).to be_none
    expect(extension).to be_ai_active
  end

  context 'when the opportunity is in proposta_enviada' do
    let(:stage) { :proposta_enviada }

    it '(c) moves a negotiation to negociacao and notifies once, keeping the assignee and with 0 private notes (RF-13)' do
      turn = run_turn(create_message('Consegue um desconto se eu pagar à vista?'), negotiation)

      expect(opportunity.reload).to have_attributes(stage: 'negociacao', escalation_reason: 'negociacao')
      expect(events('negotiation.notification_sent', correlation_id: turn.correlation_id).count).to eq(1)
      expect(conversation.reload.assignee_id).to eq(agent.id)
      expect(private_notes).to be_none
      expect(ai_replies.sole.content).to include(published_link, 'vendas@example.com')
      expect(ai_replies.sole.content).not_to include('10%')
      expect(extension).to be_ai_active
    end

    it '(c2) notifies a proposal doubt once and a later pedido_humano escalates again with 0 new notices (RF-23)' do
      first = run_turn(create_message('Não entendi um item da proposta'), escalation('duvida_proposta'))

      expect(opportunity.reload).to have_attributes(stage: 'proposta_enviada', escalation_reason: 'duvida_proposta')
      expect(events('negotiation.notification_sent', correlation_id: first.correlation_id).count).to eq(1)

      expect { run_turn(create_message('Prefiro falar com uma pessoa'), escalation('pedido_humano')) }
        .to change { events('commercial.escalated').count }.by(1)
        .and(not_change { events('negotiation.notification_sent').count })
      expect(opportunity.reload.escalation_reason).to eq('pedido_humano')
    end

    it '(e) replies to a second negotiation again with wa.me and the published e-mail, sending 0 new notices (RF-15, RF-23)' do
      run_turn(create_message('Consegue um desconto?'), negotiation)

      turn = nil
      expect { turn = run_turn(create_message('E se eu fechar hoje, melhora o preço?'), negotiation) }
        .not_to(change { events('negotiation.notification_sent').count })

      reply = ai_replies.where('messages.id > ?', turn.message_id).sole.content
      expect(reply).to include(published_link, 'vendas@example.com')
      expect(events('commercial.escalated').count).to eq(2)
    end
  end

  context 'when the opportunity is qualificado' do
    let(:stage) { :qualificado }

    it '(d) keeps the stage on a negotiation, marks it and replies with the link and the published e-mail (RF-14)' do
      turn = run_turn(create_message('Tem desconto para pagamento à vista?'), negotiation)

      expect(opportunity.reload).to have_attributes(stage: 'qualificado', escalation_reason: 'negociacao')
      expect(ScanSolo::PipelineStageEvent.where(opportunity: opportunity)).to be_none
      expect(ai_replies.sole.content).to include(published_link, 'vendas@example.com')
      expect(events('negotiation.notification_sent', correlation_id: turn.correlation_id).count).to eq(1)
      expect(extension).to be_ai_active
    end
  end

  describe '(f) an unpublished wa.me in the model reply (RF-07)' do
    let(:unpublished) { escalation('pedido_humano', 'Fale com a gente em https://wa.me/5511000000000') }

    it 'regenerates once with the violation and sends the corrected reply' do
      turn = run_turn(create_message('Quero falar com uma pessoa'), unpublished, escalation('pedido_humano'))

      expect(payloads.size).to eq(2)
      expect(payloads.last[:system]).to include('## Correção obrigatória', 'unpublished_contact')
      expect(turn.context_snapshot['output_regeneration']).to eq('first_attempt_violation' => 'unpublished_contact')
      expect(ai_replies.sole.content).to include(published_link)
      expect(ai_replies.sole.content).not_to include('5511000000000')
    end

    it 'sends a fallback reply with no unpublished number when both attempts are blocked' do
      turn = run_turn(create_message('Quero falar com uma pessoa'), unpublished)

      expect(payloads.size).to eq(2)
      expect(turn).to be_succeeded
      expect(turn.context_snapshot['output_fallback']).to eq('violation' => 'unpublished_contact')
      expect(ai_replies.sole.content).not_to include('5511000000000')
    end
  end

  it '(g) blocks a reply naming Luciano (RF-08)' do
    turn = run_turn(create_message('Com quem eu falo?'), { fixture_response: 'Fale com o Luciano, do comercial.' })

    expect(payloads.size).to eq(2)
    expect(turn.context_snapshot['output_regeneration']).to eq('first_attempt_violation' => 'internal_name')
    expect(turn.context_snapshot['output_fallback']).to eq('violation' => 'internal_name')
    expect(ai_replies.pluck(:content)).to all(satisfy { |content| !content.match?(/luciano/i) })
  end

  it '(h) hands an escalated lead to a human on a manual reply, with 0 AI replies afterwards (RF-18)' do
    run_turn(create_message('Quero falar com uma pessoa'), escalation('pedido_humano'))

    perform_enqueued_jobs(only: EventDispatcherJob) do
      Messages::MessageBuilder.new(agent, conversation, { content: 'Oi Ana, aqui é a equipe comercial' }).perform
    end
    expect(extension).to be_human_active

    ai_origin = ai_replies.where("messages.additional_attributes ->> 'scansolo_origin' = 'ai'")
    turn = nil
    expect { turn = run_turn(create_message('Ótimo, obrigado!')) }.not_to(change { ai_origin.count })
    expect(turn).to have_attributes(invocation_status: 'suppressed', failure_reason: 'human_controlled')
    expect(ai_origin.count).to eq(1)
  end

  context 'when the published snapshot has no commercial number (RF-19)' do
    let(:stage) { :proposta_enviada }

    before { publish!(commercial_whatsapp_number: nil) }

    it 'does not offer the action and replies to a negotiation with the standard reply' do
      turn = run_turn(create_message('Consegue um desconto?'), negotiation)

      expect(turn.guardrail_outcome['allowed_actions']).not_to include('escalate_to_commercial')
      expect(payloads.sole[:system]).not_to include(placeholder)
      expect(ai_replies.sole.content).to eq(I18n.t('scan_solo.negotiation.standard_reply'))
      expect(opportunity.reload.escalated_to_commercial_at).to be_nil
    end
  end

  describe '(j) the cadence of an escalated lead (RF-11)' do
    def run_due_attempts
      ScanSolo::CadenceDueAttemptJob.perform_now
    end

    it 'defers the due attempt and the follow-up of a proposal sent later, and clears the mark on ganho' do
      definition = ScanSolo::CadenceDefinition.create!(stage: 'em_contato', version: 1, offsets: [2])
      ScanSolo::CadenceDefinition.create!(stage: 'proposta_enviada', version: 1, offsets: [24])
      run_turn(create_message('Quero falar com uma pessoa'), escalation('pedido_humano'))

      # Enrolled after the turn: the customer's reply itself ends a running cadence (RF-28).
      attempt = ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: definition).attempts.sole
      attempt.update!(scheduled_at: 1.minute.ago)
      expect { run_due_attempts }.not_to change(ai_replies, :count)
      expect(attempt.reload).to have_attributes(result: 'scheduled', last_block_reason: 'commercial_escalated')

      version = ScanSolo::Proposal.create!(opportunity: opportunity).versions.create!(generate_correlation_id: SecureRandom.uuid)
      version.update!(status: :sent)
      ScanSolo::Pipeline::StageTransitionService.new(opportunity: opportunity.reload, target_stage: 'proposta_enviada').call
      follow_up = opportunity.cadence_enrollments.active.sole.attempts.order(:step).first
      follow_up.update!(scheduled_at: 1.minute.ago)
      expect { run_due_attempts }.not_to change(ai_replies, :count)
      expect(follow_up.reload).to have_attributes(result: 'scheduled', last_block_reason: 'commercial_escalated')

      ScanSolo::Pipeline::StageTransitionService.new(opportunity: opportunity.reload, target_stage: 'ganho').call
      expect(opportunity.reload).to have_attributes(escalated_to_commercial_at: nil, escalation_reason: nil)
      expect(opportunity).not_to be_escalated_to_commercial
      expect(events('commercial.escalated').count).to eq(1)
    end
  end

  it '(k) calls the LLM exactly once per approved attempt, with 0 HTTP requests (RNF-04)' do
    run_turn(create_message('Quero falar com uma pessoa'), escalation('pedido_humano'))
    expect(payloads.size).to eq(1)

    run_turn(create_message('Obrigado!'), { fixture_response: 'Por nada!' })
    expect(payloads.size).to eq(2)

    expect(ai_replies.count).to eq(2)
    expect(a_request(:any, /.*/)).not_to have_been_made
  end
end
