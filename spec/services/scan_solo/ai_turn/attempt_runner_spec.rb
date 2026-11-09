# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::AiTurn::AttemptRunner do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact,
                     content: 'Segue o documento')
  end
  let!(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_qualificacao)
  end
  let(:config) { ScanSolo::AiAgentConfig.published_for(account) }
  let!(:turn) do
    ScanSolo::AiTurn.create!(message: message, conversation: conversation, correlation_id: SecureRandom.uuid,
                             guardrail_outcome: { 'allowed_actions' => %w[qualification_field private_note] })
  end
  let(:pending_updates) do
    [
      { key: 'cnpj', value: '12.345.678/0001-90', source_attachment_id: nil },
      { key: 'empresa', value: 'ACME Engenharia Ltda', source_attachment_id: nil }
    ]
  end
  let(:actions) { [{ 'action_id' => 'private_note', 'params' => { 'content' => 'nota' } }] }
  let(:asked_fields) { [] }
  let(:result) do
    ScanSolo::AiTurn::ModelInvoker::Result.new(content: 'Pode me informar o bairro?', actions: actions, asked_fields: asked_fields,
                                               summary: false, provider: 'scansolo_test_mode', model: 'scansolo-mock-llm')
  end

  before do
    draft = ScanSolo::AiAgentConfig.draft_for!(account)
    draft.update!(name: 'Agente ScanSolo', enabled: true, allowed_inbox_ids: [inbox.id], required_qualification_fields: %w[Metragem])
    ScanSolo::AiAgent::PublishService.new(account: account).call
    opportunity.lead_state.update!(fields: { 'cidade_uf' => { 'value' => 'Rio de Janeiro / RJ', 'status' => 'confirmado' } })
  end

  def run_attempt
    described_class.call(turn: turn, message: message, config: config, result: result, opportunity: opportunity, pending_updates: pending_updates)
  end

  def ai_replies
    conversation.messages.outgoing.where(private: false)
  end

  context 'when the validator blocks the reply' do
    let(:asked_fields) { ['cidade_uf'] }

    it 'returns the violation and rolls back every change of the attempt' do
      outcome = nil

      expect { outcome = run_attempt }
        .not_to(change { [opportunity.lead_state.reload.fields, ScanSolo::LeadStateEvent.count, conversation.messages.count] })

      expect(outcome).to have_attributes(status: :blocked, violation: :confirmed_field_question)
      expect(ScanSolo::AgentActionExecution.count).to eq(0)
      expect(turn.reload).to be_pending
    end
  end

  context 'when the reply is approved' do
    it 'writes the extractions as inferido before sending the reply' do
      expect(run_attempt).to have_attributes(status: :sent, violation: nil)

      expect(opportunity.lead_state.reload.fields['cnpj']).to include('value' => '12.345.678/0001-90', 'status' => 'inferido',
                                                                      'source_message_id' => message.id)
      expect(ScanSolo::LeadStateEvent.where(key: %w[cnpj empresa]).pluck(:created_at)).to all(be <= ai_replies.sole.created_at)
      expect(ScanSolo::AgentActionExecution.sole.idempotency_key).to eq("#{turn.correlation_id}:0:private_note")
      expect(turn.reload).to have_attributes(invocation_status: 'succeeded', response_message_id: ai_replies.sole.id)
    end

    it 'concludes the qualification when an action confirms the last required field' do
      actions.replace([{ 'action_id' => 'qualification_field', 'params' => { 'fields' => { 'metragem' => '500' } } }])

      run_attempt

      expect(opportunity.lead_state.reload).to be_concluida
      expect(opportunity.reload).to be_qualificado
    end
  end

  describe 'RF-35: negotiation signal' do
    let(:email_inbox) { create(:channel_email, account: account, email: 'atendimento.comercial@scansolo.com.br').inbox }
    let(:pending_updates) { [] }
    let(:actions) { [{ 'action_id' => 'lead_state_update', 'params' => { 'negotiation_requested' => true } }] }
    let(:result) do
      ScanSolo::AiTurn::ModelInvoker::Result.new(content: 'Consigo fazer por R$ 11.000,00 à vista.', actions: actions, asked_fields: ['bairro'],
                                                 summary: false, provider: 'scansolo_test_mode', model: 'scansolo-mock-llm')
    end
    let(:extension) { ScanSolo::ConversationExtension.resolve_for(conversation) }

    before do
      turn.update!(guardrail_outcome: { 'allowed_actions' => %w[lead_state_update private_note] })
      ScanSolo::AiAgentConfig.draft_for!(account).update!(quote_inbox_id: email_inbox.id)
      ScanSolo::AiAgent::PublishService.new(account: account).call
    end

    def notifications
      Message.where(inbox: email_inbox, message_type: :outgoing)
    end

    context 'when the opportunity is in proposta_enviada' do
      before { opportunity.update!(stage: :proposta_enviada) }

      it 'sends the exact standard reply, moves to negociacao, keeps the AI active and publishes once after the commit' do
        ActiveRecord::Base.transaction do
          expect(run_attempt).to have_attributes(status: :sent, violation: nil)
          expect(notifications.count).to eq(0)
        end

        expect(ai_replies.sole.content).to eq('Vou verificar isso com nosso comercial. Só um momento.')
        expect(opportunity.reload).to be_negociacao
        expect(ScanSolo::PipelineStageEvent.where(opportunity: opportunity).sole)
          .to have_attributes(from_stage: 'proposta_enviada', to_stage: 'negociacao')
        expect([extension.reload.ai_control_state, conversation.messages.where(private: true).count]).to eq(['ai_active', 0])
        expect(notifications.count).to eq(1)
      end

      it 'stops the cadence with no attempt left scheduled' do
        definition = ScanSolo::CadenceDefinition.create!(stage: 'proposta_enviada', version: 1, offsets: [24, 72])
        ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: definition)

        run_attempt

        expect(opportunity.cadence_enrollments.where(status: :active)).to be_none
        expect(ScanSolo::CadenceAttempt.where(result: 'scheduled')).to be_none
      end

      it 'sends the standard reply instead of a model reply that quotes a price' do
        run_attempt

        expect(ai_replies.sole.content).to eq('Vou verificar isso com nosso comercial. Só um momento.')
        expect(ai_replies.sole.content).not_to include('R$')
      end

      it 'next customer message is still handled by the AI, with no handoff (escalação comercial RF-13)' do
        run_attempt
        next_message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                                        sender: contact, content: 'E então?')

        ScanSolo::AiTurn::TurnOrchestrator.call(message: next_message, llm_provider: ScanSolo::TestMode::MockLlmProvider)

        expect(ScanSolo::AiTurn.find_by!(message_id: next_message.id).failure_reason).not_to eq('human_controlled')
        expect(extension.reload).to be_ai_active
      end
    end

    context 'when the opportunity is already in negociacao with the AI active' do
      before { opportunity.update!(stage: :negociacao) }

      it 'sends the standard reply, keeps the AI active and notifies without a stage event' do
        run_attempt

        expect(ai_replies.sole.content).to eq('Vou verificar isso com nosso comercial. Só um momento.')
        expect(ScanSolo::PipelineStageEvent.where(opportunity: opportunity)).to be_none
        expect(extension.reload).to be_ai_active
        expect(notifications.count).to eq(1)
      end
    end

    context 'when the opportunity is still in qualification' do
      let(:result) do
        ScanSolo::AiTurn::ModelInvoker::Result.new(content: 'Pode me informar a metragem?', actions: actions, asked_fields: [],
                                                   summary: false, provider: 'scansolo_test_mode', model: 'scansolo-mock-llm')
      end

      it 'ignores the signal and sends the model reply' do
        definition = ScanSolo::CadenceDefinition.create!(stage: 'em_qualificacao', version: 1, offsets: [24, 72])
        enrollment = ScanSolo::Cadence::EnrollmentService.call(opportunity: opportunity, cadence_definition: definition)

        expect(run_attempt).to have_attributes(status: :sent)

        expect(ai_replies.sole.content).to eq('Pode me informar a metragem?')
        expect(opportunity.reload).to be_em_qualificacao
        expect(extension.reload).to be_ai_active
        expect(enrollment.reload).to be_active
        expect(ScanSolo::AuditEvent.where(event_type: 'negotiation.requested')).to be_none
        expect(notifications).to be_none
      end
    end
  end

  describe 'escalação comercial: link, negotiation and validator inputs (RF-05, RF-06, RF-13..RF-15, RF-19, RF-23)' do
    let(:pending_updates) { [] }
    let(:reason) { 'pedido_humano' }
    let(:actions) { [{ 'action_id' => 'escalate_to_commercial', 'params' => { 'reason' => reason } }] }
    let(:content) { "Fale com o Artur pelo WhatsApp: #{ScanSolo::Commercial::WhatsappLink::PLACEHOLDER}" }
    let(:result) do
      ScanSolo::AiTurn::ModelInvoker::Result.new(content: content, actions: actions, asked_fields: [], summary: false,
                                                 provider: 'scansolo_test_mode', model: 'scansolo-mock-llm')
    end

    before do
      allow(ScanSolo::Notifications::EmailAdapter).to receive(:call)
        .and_return(ScanSolo::Notifications::Publisher::Result.new(success: true, reason: nil))
      allow(ScanSolo::Notifications::Publisher).to receive(:call).and_call_original
      turn.update!(guardrail_outcome: { 'allowed_actions' => %w[escalate_to_commercial lead_state_update private_note] })
      ScanSolo::AiAgentConfig.draft_for!(account).update!(commercial_whatsapp_number: '+5511999999999',
                                                          quote_recipient_email: 'vendas@example.com')
      ScanSolo::AiAgent::PublishService.new(account: account).call
    end

    def sent_reply
      ai_replies.sole.content
    end

    def escalation_events
      ScanSolo::AuditEvent.where(subject: opportunity, event_type: 'commercial.escalated')
    end

    it 'sends 1 AI reply with the link exactly once in place of the placeholder' do
      expect(run_attempt).to have_attributes(status: :sent, violation: nil)

      expect(ai_replies.sole.additional_attributes).to include('scansolo_origin' => 'ai')
      expect(sent_reply.scan('https://wa.me/5511999999999?text=').size).to eq(1)
      expect(sent_reply).not_to include('{{')
      expect(opportunity.reload).to have_attributes(escalation_reason: 'pedido_humano')
      expect(ScanSolo::ConversationExtension.resolve_for(conversation)).to be_ai_active
    end

    context 'when the model reply has no placeholder' do
      let(:content) { 'Vou te passar o contato do nosso comercial.' }

      it 'appends the link once' do
        run_attempt

        expect(sent_reply).to start_with('Vou te passar o contato do nosso comercial.')
        expect(sent_reply.scan('https://wa.me/').size).to eq(1)
      end
    end

    context 'when the model repeats the placeholder' do
      let(:content) { "Link: #{ScanSolo::Commercial::WhatsappLink::PLACEHOLDER} de novo #{ScanSolo::Commercial::WhatsappLink::PLACEHOLDER}" }

      it 'keeps only the first occurrence as the link' do
        run_attempt

        expect(sent_reply.scan('https://wa.me/').size).to eq(1)
        expect(sent_reply).not_to include('{{')
      end
    end

    it 'builds the link from the published number only, never the draft one' do
      ScanSolo::AiAgentConfig.draft_for!(account).update!(commercial_whatsapp_number: '+5521888888888')

      run_attempt

      expect(sent_reply).to include('https://wa.me/5511999999999')
      expect(sent_reply).not_to include('5521888888888')
    end

    context 'when the reply carries an unpublished contact' do
      let(:content) { 'Fale com a gente em https://wa.me/5511000000000' }

      it 'blocks it and rolls back the mark, the audit and the notice e-mail' do
        ActiveRecord::Base.transaction do
          expect(run_attempt).to have_attributes(status: :blocked, violation: :unpublished_contact)
        end

        expect(opportunity.reload.escalated_to_commercial_at).to be_nil
        expect(escalation_events).to be_none
        expect(ScanSolo::Notifications::Publisher).not_to have_received(:call)
        expect(ai_replies).to be_none
      end
    end

    it "accepts the contact's own phone and the lead state telefone" do
      message.conversation.contact.update!(phone_number: '+5521977776666')
      opportunity.lead_state.update!(fields: { 'telefone' => { 'value' => '(31) 98888-7777', 'status' => 'confirmado' } })
      result.content = "Anotei seus telefones +5521977776666 e (31) 98888-7777. #{content}"

      expect(run_attempt).to have_attributes(status: :sent, violation: nil)
    end

    describe 'negotiation' do
      let(:actions) { [{ 'action_id' => 'lead_state_update', 'params' => { 'negotiation_requested' => true } }] }
      let(:content) { 'Consigo fazer por R$ 11.000,00 à vista.' }

      context 'when the opportunity is qualificado' do
        before { opportunity.update!(stage: :qualificado) }

        it 'keeps the stage, writes 1 mark and replies with the link and the published e-mail' do
          ActiveRecord::Base.transaction { expect(run_attempt).to have_attributes(status: :sent, violation: nil) }

          expect(opportunity.reload).to have_attributes(stage: 'qualificado', escalation_reason: 'negociacao')
          expect([escalation_events.count, ScanSolo::PipelineStageEvent.where(opportunity: opportunity).count]).to eq([1, 0])
          expect(sent_reply).to include('https://wa.me/', 'vendas@example.com')
          expect(sent_reply).not_to include('comercial@scansolo.com.br', '{{')
          expect(ScanSolo::Notifications::Publisher).to have_received(:call).once
        end

        it 'sends an escalation reply that passes the price claim check' do
          expect(run_attempt).to have_attributes(status: :sent, violation: nil)

          expect(sent_reply).not_to match(ScanSolo::AiTurn::OutputValidator::PRICE_PATTERN)
        end
      end

      context 'when the opportunity is proposta_enviada' do
        before { opportunity.update!(stage: :proposta_enviada) }

        it 'moves it to negociacao and escalates with the escalation reply' do
          run_attempt

          expect(opportunity.reload).to be_negociacao
          expect(opportunity.escalation_reason).to eq('negociacao')
          expect(sent_reply.scan('https://wa.me/').size).to eq(1)
          expect(ScanSolo::ConversationExtension.resolve_for(conversation)).to be_ai_active
        end
      end

      context 'when the opportunity was already escalated' do
        before do
          opportunity.update!(stage: :negociacao, escalated_to_commercial_at: 1.day.ago, escalation_reason: 'pedido_humano')
        end

        it 'sends no notice e-mail and still replies with the link and the published e-mail' do
          ActiveRecord::Base.transaction { run_attempt }

          expect(ScanSolo::Notifications::Publisher).not_to have_received(:call)
          expect(sent_reply).to include('https://wa.me/', 'vendas@example.com')
          expect(opportunity.reload.escalation_reason).to eq('negociacao')
        end
      end

      context 'when no commercial number is published' do
        let(:content) { "Vou te passar o contato: #{ScanSolo::Commercial::WhatsappLink::PLACEHOLDER}" }

        before do
          ScanSolo::AiAgentConfig.draft_for!(account).update!(commercial_whatsapp_number: nil)
          ScanSolo::AiAgent::PublishService.new(account: account).call
          opportunity.update!(stage: :proposta_enviada)
        end

        it 'sends the standard reply with no link or placeholder and writes no mark' do
          expect(run_attempt).to have_attributes(status: :sent, violation: nil)

          expect(sent_reply).to eq(I18n.t('scan_solo.negotiation.standard_reply'))
          expect(sent_reply).not_to include('wa.me', '{{')
          expect(opportunity.reload.escalated_to_commercial_at).to be_nil
          expect(turn.reload).not_to be_failed
        end
      end
    end

    context 'when the model asks a proposal doubt' do
      let(:reason) { 'duvida_proposta' }

      it 'runs the negotiation request without moving the stage in qualificado (RF-14)' do
        opportunity.update!(stage: :qualificado)

        run_attempt

        expect(opportunity.reload).to have_attributes(stage: 'qualificado', escalation_reason: 'duvida_proposta')
        expect(ScanSolo::AuditEvent.where(event_type: 'negotiation.requested').sole.payload)
          .to include('escalation_reason' => 'duvida_proposta')
        expect(sent_reply.scan('https://wa.me/').size).to eq(1)
      end

      it 'escalates only through the action in proposta_enviada (RF-23)' do
        opportunity.update!(stage: :proposta_enviada)

        ActiveRecord::Base.transaction { run_attempt }

        expect(opportunity.reload).to have_attributes(stage: 'proposta_enviada', escalation_reason: 'duvida_proposta')
        expect(ScanSolo::AuditEvent.where(event_type: 'negotiation.requested')).to be_none
        expect(ScanSolo::Notifications::Publisher).to have_received(:call).once
      end
    end
  end

  describe 'bulk collection start (proposta-template-local RF-38 c, e)' do
    let(:relevant) { %w[area metragem profundidade integracao_seguranca] }
    let(:accept_bulk) { [{ 'action_id' => 'lead_state_update', 'params' => { 'collection_mode' => 'em_bloco' } }] }

    before do
      writer = ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state)
      turn.update!(guardrail_outcome: { 'allowed_actions' => %w[lead_state_update private_note] })
      { 'tipo_servico' => 'GeoRadar', 'restricoes_acesso' => 'Portaria', 'prazo_desejado' => '30 dias', 'condicoes_especiais' => 'Nenhuma' }
        .each { |key, value| writer.apply_field!(key: key, value: value, status: 'confirmado', source_message_id: nil) }
      writer.record_collection_offer!(at: 1.minute.ago, source_message_id: nil)
    end

    it 'blocks the acceptance turn that asks only 3 of the relevant pending fields and rolls the choice back' do
      actions.replace(accept_bulk)
      asked_fields.replace(relevant.first(3))

      expect(run_attempt).to have_attributes(status: :blocked, violation: :bulk_incomplete)
      expect(opportunity.lead_state.reload.collection_mode).to be_nil
      expect(ai_replies).to be_none
    end

    it 'sends the acceptance turn that asks every relevant pending field' do
      actions.replace(accept_bulk)
      asked_fields.replace(relevant)

      expect(run_attempt).to have_attributes(status: :sent, violation: nil)
      expect(opportunity.lead_state.reload.collection_mode).to eq('em_bloco')
    end

    it 'regenerates the attempt once after bulk_incomplete' do
      calls = []
      responses = [{ fixture_actions: accept_bulk, fixture_asked_fields: relevant.first(3) },
                   { fixture_actions: accept_bulk, fixture_asked_fields: relevant }]
      provider = lambda do |**kwargs|
        calls << kwargs[:payload]
        ScanSolo::TestMode::MockLlmProvider.call(**kwargs, **responses.fetch(calls.size - 1))
      end

      ScanSolo::AiTurn::TurnOrchestrator.call(message: message, llm_provider: provider)

      expect(calls.size).to eq(2)
      expect(calls.last[:system]).to include('rejeitada pela violação bulk_incomplete')
      expect(turn.reload).to be_succeeded
      expect(turn.context_snapshot['output_regeneration']).to eq('first_attempt_violation' => 'bulk_incomplete')
      expect(opportunity.lead_state.reload.collection_mode).to eq('em_bloco')
      expect(ScanSolo::LeadStateEvent.where(key: 'collection_mode').count).to eq(1)
      expect(ai_replies.count).to eq(1)
    end
  end

  %w[awaiting_human human_active].each do |state|
    it "keeps the AI silent while the conversation is #{state} (RF-40)" do
      ScanSolo::ConversationExtension.resolve_for(conversation).update!(ai_control_state: state)

      ScanSolo::AiTurn::TurnOrchestrator.call(message: message, llm_provider: ScanSolo::TestMode::MockLlmProvider)

      expect(turn.reload).to have_attributes(invocation_status: 'suppressed', failure_reason: 'human_controlled')
      expect(ai_replies).to be_none
    end
  end

  it 'lets an action exception propagate' do
    actions.replace([{ 'action_id' => 'stage_transition', 'params' => { 'target_stage' => 'qualificado' } }])

    expect { run_attempt }.to raise_error(ScanSolo::Actions::Executor::UnregisteredActionError)
  end
end
