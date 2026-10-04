require 'rails_helper'

RSpec.describe ScanSolo::LeadState::CompletionService do
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account, name: '', email: nil, phone_number: nil, custom_attributes: {}) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:stage) { :em_qualificacao }
  let(:opportunity) { ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: stage) }
  let(:writer) { ScanSolo::LeadState::Writer.new(lead_state: opportunity.lead_state) }
  let(:required_fields) { ['Área ou extensão', 'Cidade / UF'] }
  let(:message) { create(:message, account: account, conversation: conversation, message_type: :incoming) }
  let(:turn) { ScanSolo::AiTurn.create!(message: message, conversation: conversation, correlation_id: SecureRandom.uuid) }
  let(:lead_state) { opportunity.lead_state.reload }
  let(:completion_audits) { ScanSolo::AuditEvent.where(event_type: 'lead_state.qualification_completed') }

  before do
    ScanSolo::AiAgentConfig.draft_for!(account).update!(name: 'Agente', enabled: true, required_qualification_fields: required_fields)
    ScanSolo::AiAgent::PublishService.new(account: account).call
    writer.apply_field!(key: 'cidade_uf', value: 'Rio/RJ', status: 'confirmado', source_message_id: message.id)
  end

  context 'when the last required field is confirmed' do
    before { writer.apply_field!(key: 'area', value: '800 m²', status: 'confirmado', source_message_id: message.id) }

    it 'concludes, moves em_qualificacao to qualificado and records the next action and one audit event' do
      described_class.call(opportunity: opportunity, turn: turn)

      expect(lead_state).to have_attributes(qualification_status: 'concluida', next_action: 'aguardar_cliente',
                                            next_action_source_message_id: message.id)
      expect(lead_state.qualification_completed_at).to be_present
      expect(opportunity.reload.stage).to eq('qualificado')
      expect(opportunity.stage_events.pluck(:from_stage, :to_stage)).to eq([%w[em_qualificacao qualificado]])
      expect(completion_audits.sole).to have_attributes(correlation_id: turn.correlation_id, subject: lead_state)
    end

    it 'does nothing on a second call' do
      described_class.call(opportunity: opportunity, turn: turn)

      expect { described_class.call(opportunity: opportunity, turn: turn) }
        .to not_change(ScanSolo::PipelineStageEvent, :count)
        .and(not_change(ScanSolo::AuditEvent, :count))
        .and(not_change(ScanSolo::LeadStateEvent, :count))
    end

    context 'with an em_contato opportunity' do
      let(:stage) { :em_contato }

      it 'passes through em_qualificacao with one stage event per transition' do
        described_class.call(opportunity: opportunity, turn: turn)

        expect(opportunity.stage_events.order(:id).pluck(:from_stage, :to_stage))
          .to eq([%w[em_contato em_qualificacao], %w[em_qualificacao qualificado]])
      end
    end

    context 'with a novo_lead opportunity' do
      let(:stage) { :novo_lead }

      it 'passes through em_qualificacao with one stage event per transition' do
        described_class.call(opportunity: opportunity, turn: turn)

        expect(opportunity.stage_events.order(:id).pluck(:from_stage, :to_stage))
          .to eq([%w[novo_lead em_qualificacao], %w[em_qualificacao qualificado]])
      end
    end

    context 'with a proposta_enviada opportunity' do
      let(:stage) { :proposta_enviada }

      it 'concludes without any stage transition' do
        described_class.call(opportunity: opportunity, turn: turn)

        expect(lead_state).to be_concluida
        expect(opportunity.reload.stage).to eq('proposta_enviada')
        expect(opportunity.stage_events).to be_empty
      end
    end

    it 'records the intent default when the model recorded no next action in the turn (RF-15)' do
      writer.set_intent!(intent: 'visita', source_message_id: message.id)

      described_class.call(opportunity: opportunity, turn: turn)

      expect(lead_state.next_action).to eq('avaliacao_tecnica')
      expect(opportunity.reload.stage).to eq('qualificado')
    end

    it 'keeps the next action the model recorded in the same turn' do
      writer.set_intent!(intent: 'visita', source_message_id: message.id)
      writer.record_next_action!(value: 'proposta', source_message_id: message.id)

      described_class.call(opportunity: opportunity, turn: turn)

      expect(lead_state.next_action).to eq('proposta')
      expect(lead_state.events.where(subject: 'next_action').count).to eq(1)
    end

    it 'replaces a next action recorded in an earlier turn with the intent default' do
      earlier = create(:message, account: account, conversation: conversation, message_type: :incoming)
      writer.record_next_action!(value: 'atendimento_humano', source_message_id: earlier.id)
      writer.set_intent!(intent: 'orcamento', source_message_id: message.id)

      described_class.call(opportunity: opportunity, turn: turn)

      expect(lead_state).to have_attributes(next_action: 'proposta', next_action_source_message_id: message.id)
    end
  end

  describe 'quote request trigger (RF-12)' do
    before do
      writer.set_intent!(intent: 'orcamento', source_message_id: message.id)
      writer.apply_field!(key: 'area', value: '800 m²', status: 'confirmado', source_message_id: message.id)
    end

    it 'enqueues the quote request job only after the transaction commits' do
      ActiveRecord::Base.transaction do
        described_class.call(opportunity: opportunity, turn: turn)

        expect(ScanSolo::QuoteRequestJob).not_to have_been_enqueued
      end

      expect(ScanSolo::QuoteRequestJob).to have_been_enqueued.with(opportunity.id).once
    end

    it 'enqueues nothing when the attempt rolls back' do
      ActiveRecord::Base.transaction do
        described_class.call(opportunity: opportunity, turn: turn)
        raise ActiveRecord::Rollback
      end

      expect(ScanSolo::QuoteRequestJob).not_to have_been_enqueued
    end

    it 'enqueues nothing for a next action other than proposta' do
      writer.set_intent!(intent: 'duvida', source_message_id: message.id)

      described_class.call(opportunity: opportunity, turn: turn)

      expect(lead_state).to be_concluida
      expect(ScanSolo::QuoteRequestJob).not_to have_been_enqueued
    end

    it 'enqueues nothing when the lead state backfill concludes an opportunity' do
      opportunity.update!(stage: :qualificado)
      ScanSolo::LeadStateEvent.delete_all
      ScanSolo::LeadState.delete_all
      Rake::Task['scansolo:backfill_lead_states'].reenable

      expect { Rake::Task['scansolo:backfill_lead_states'].invoke }.to output.to_stdout

      expect(opportunity.reload.lead_state).to be_concluida
      expect(ScanSolo::QuoteRequestJob).not_to have_been_enqueued
      expect(ScanSolo::QuoteRequest.count).to eq(0)
    end
  end

  it 'does not conclude while a required field is only inferido (RF-04)' do
    writer.apply_field!(key: 'area', value: '800 m²', status: 'inferido', source_message_id: message.id)

    expect { described_class.call(opportunity: opportunity, turn: turn) }.not_to change(ScanSolo::AuditEvent, :count)
    expect(lead_state).to be_em_andamento
    expect(opportunity.reload.stage).to eq('em_qualificacao')
  end

  context 'with a required CNPJ inferred from a PDF' do
    let(:required_fields) { ['Cidade / UF', 'CNPJ'] }

    it 'does not conclude until the customer confirms it' do
      writer.apply_field!(key: 'cnpj', value: '12.345.678/0001-90', status: 'inferido', source_message_id: message.id, source_attachment_id: 1)
      described_class.call(opportunity: opportunity, turn: turn)
      expect(lead_state).to be_em_andamento

      writer.apply_field!(key: 'cnpj', value: '12.345.678/0001-90', status: 'confirmado', source_message_id: message.id)
      described_class.call(opportunity: opportunity, turn: turn)
      expect(lead_state.reload).to be_concluida
    end
  end

  context 'without required fields in the config' do
    let(:required_fields) { [] }

    it 'never concludes' do
      described_class.call(opportunity: opportunity, turn: turn)

      expect(lead_state).to be_em_andamento
    end
  end

  it 'keeps a concluida qualification when the config later requires a faltante field (RF-21)' do
    writer.apply_field!(key: 'area', value: '800 m²', status: 'confirmado', source_message_id: message.id)
    described_class.call(opportunity: opportunity, turn: turn)
    ScanSolo::AiAgentConfig.draft_for!(account).update!(required_qualification_fields: [*required_fields, 'Bairro'])
    ScanSolo::AiAgent::PublishService.new(account: account).call

    expect { described_class.call(opportunity: opportunity, turn: turn) }.not_to(change { lead_state.reload.attributes })
    expect(lead_state).to be_concluida
  end
end
