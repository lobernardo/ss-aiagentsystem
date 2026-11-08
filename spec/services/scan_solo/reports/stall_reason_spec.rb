# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Reports::StallReason do
  let(:now) { Time.zone.parse('2026-11-08T15:00:00Z') }
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:opportunity) do
    ScanSolo::PipelineOpportunity.create!(account: account, contact: contact, conversation: conversation, stage: :em_contato)
  end
  let!(:extension) { ScanSolo::ConversationExtension.create!(conversation: conversation, ai_control_state: :ai_active) }
  let(:em_contato_definition) { ScanSolo::CadenceDefinition.create!(stage: 'em_contato', version: 1, offsets: [24, 48]) }
  let(:proposta_definition) { ScanSolo::CadenceDefinition.create!(stage: 'proposta_enviada', version: 1, offsets: [24, 72]) }
  let(:enrollment) { ScanSolo::CadenceEnrollment.create!(opportunity: opportunity, cadence_definition: em_contato_definition) }

  # Same shape the report list uses: every association the rule reads is preloaded.
  def preloaded_opportunity
    ScanSolo::PipelineOpportunity.includes(:conversation_extension, cadence_enrollments: %i[cadence_definition attempts]).find(opportunity.id)
  end

  def reason_for(commercial_status: 'nao_encaminhado', legacy_bulk: false)
    described_class.call(opportunity: preloaded_opportunity, now: now, commercial_status: commercial_status,
                         legacy_bulk: legacy_bulk)[:stall_reason]
  end

  def schedule_attempt(scheduled_at:, step: 1, last_block_reason: nil)
    enrollment.attempts.create!(step: step, cadence_version: 1, template_reference: 'scansolo_follow_up',
                                scheduled_at: scheduled_at, last_block_reason: last_block_reason)
  end

  describe 'one case per RF-05 reason' do
    it '1: a conversation not under AI control is em_atendimento_humano' do
      extension.update!(ai_control_state: :human_active)

      expect(reason_for).to eq('em_atendimento_humano')
    end

    it '2: a request waiting on the commercial contact is aguardando_artur' do
      opportunity.update!(stage: :qualificado)

      expect(reason_for(commercial_status: 'aguardando_artur')).to eq('aguardando_artur')
    end

    it '3: an active current-stage enrollment with a template-blocked scheduled attempt is cadencia_bloqueada_template_meta' do
      schedule_attempt(scheduled_at: now + 1.hour, last_block_reason: 'params_mismatch')

      expect(reason_for).to eq('cadencia_bloqueada_template_meta')

      enrollment.attempts.first.update!(last_block_reason: 'template_missing')
      expect(reason_for(commercial_status: 'nao_encaminhado')).to eq('cadencia_bloqueada_template_meta')
    end

    it '4: an active current-stage enrollment with an overdue scheduled attempt is followup_vencido_nao_enviado' do
      schedule_attempt(scheduled_at: now - 1.minute, last_block_reason: 'outside_window')

      expect(reason_for).to eq('followup_vencido_nao_enviado')
    end

    it '5: a bulk-handled manual proposal is proposta_manual_sem_cadencia' do
      opportunity.update!(stage: :proposta_enviada)
      ScanSolo::CadenceEnrollment.create!(opportunity: opportunity, cadence_definition: proposta_definition, status: :cancelled)

      expect(reason_for(commercial_status: 'proposta_enviada_manual', legacy_bulk: true)).to eq('proposta_manual_sem_cadencia')
    end

    it '6: a cadence stage without a scheduled follow-up is sem_followup_agendado' do
      expect(reason_for).to eq('sem_followup_agendado')

      enrollment.update!(status: :cancelled)
      expect(reason_for).to eq('sem_followup_agendado')
    end

    it '6: an active or paused current-stage enrollment without scheduled attempts is sem_followup_agendado' do
      schedule_attempt(scheduled_at: now - 1.day).update!(result: :sent)

      expect(reason_for).to eq('sem_followup_agendado')

      enrollment.update!(status: :paused)
      expect(reason_for(commercial_status: 'nao_encaminhado')).to eq('sem_followup_agendado')
    end

    it '7: a completed current-stage enrollment is cadencia_concluida_sem_resposta' do
      enrollment.update!(status: :completed)

      expect(reason_for).to eq('cadencia_concluida_sem_resposta')
    end

    it '8: an active current-stage enrollment with a future scheduled attempt is aguardando_resposta_do_lead' do
      schedule_attempt(scheduled_at: now)
      schedule_attempt(scheduled_at: now + 1.day, step: 2)

      expect(reason_for).to eq('aguardando_resposta_do_lead')
    end

    it '9: a qualified opportunity never forwarded is qualificado_sem_encaminhamento' do
      opportunity.update!(stage: :qualificado)

      expect(reason_for(commercial_status: 'nao_encaminhado')).to eq('qualificado_sem_encaminhamento')
    end

    it '10: anything else is outro' do
      opportunity.update!(stage: :qualificado)
      expect(reason_for(commercial_status: 'resposta_recebida')).to eq('outro')

      opportunity.update!(stage: :negociacao)
      expect(reason_for(commercial_status: 'proposta_enviada')).to eq('outro')
    end
  end

  describe 'precedence' do
    it '(i) human attendance wins over a template-blocked cadence' do
      extension.update!(ai_control_state: :awaiting_human)
      schedule_attempt(scheduled_at: now + 1.hour, last_block_reason: 'template_missing')

      expect(reason_for).to eq('em_atendimento_humano')
    end

    it '(ii) a bulk legacy lead is proposta_manual_sem_cadencia, never sem_followup_agendado' do
      opportunity.update!(stage: :proposta_enviada)
      ScanSolo::CadenceEnrollment.create!(opportunity: opportunity, cadence_definition: proposta_definition, status: :cancelled)

      expect(reason_for(commercial_status: 'proposta_enviada_manual', legacy_bulk: true)).to eq('proposta_manual_sem_cadencia')
      expect(reason_for(commercial_status: 'proposta_enviada_manual', legacy_bulk: false)).to eq('sem_followup_agendado')
    end

    it '(iii) a single-mode manual lead with a completed cadence is cadencia_concluida_sem_resposta' do
      opportunity.update!(stage: :proposta_enviada)
      ScanSolo::CadenceEnrollment.create!(opportunity: opportunity, cadence_definition: proposta_definition, status: :completed)

      expect(reason_for(commercial_status: 'proposta_enviada_manual', legacy_bulk: false)).to eq('cadencia_concluida_sem_resposta')
    end

    it 'reads the most recent enrollment of the current stage only' do
      enrollment.update!(status: :completed, created_at: now - 3.days)
      newer = ScanSolo::CadenceEnrollment.create!(opportunity: opportunity, cadence_definition: em_contato_definition, created_at: now - 1.day)
      newer.attempts.create!(step: 1, cadence_version: 1, template_reference: 'scansolo_follow_up', scheduled_at: now + 1.day)
      ScanSolo::CadenceEnrollment.create!(opportunity: opportunity, cadence_definition: proposta_definition, status: :completed,
                                          created_at: now)

      expect(reason_for).to eq('aguardando_resposta_do_lead')
    end
  end

  it 'maps each of the 10 reasons to one suggested action i18n key (RF-06)' do
    expect(described_class::SUGGESTED_ACTIONS.size).to eq(10)
    expect(described_class::SUGGESTED_ACTIONS.keys).to eq(described_class::REASONS)
    expect(described_class::SUGGESTED_ACTIONS['outro']).to eq('SCANSOLO.REPORTS.SUGGESTED_ACTIONS.OUTRO')
    expect(described_class.call(opportunity: preloaded_opportunity, now: now, commercial_status: 'nao_encaminhado', legacy_bulk: false))
      .to eq(stall_reason: 'sem_followup_agendado', suggested_action: 'SCANSOLO.REPORTS.SUGGESTED_ACTIONS.SEM_FOLLOWUP_AGENDADO')
  end

  it 'runs 0 SQL queries over preloaded data (RNF-03)' do
    schedule_attempt(scheduled_at: now + 1.hour, last_block_reason: 'template_missing')
    ScanSolo::CadenceEnrollment.create!(opportunity: opportunity, cadence_definition: proposta_definition, status: :completed)
    preloaded = preloaded_opportunity
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == 'SCHEMA' }

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      ScanSolo::Reports::CommercialStatus::VALUES.each do |status|
        described_class.call(opportunity: preloaded, now: now, commercial_status: status, legacy_bulk: true)
      end
    end

    expect(queries).to be_empty
  end
end
