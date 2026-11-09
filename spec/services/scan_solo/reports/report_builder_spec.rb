# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Reports::ReportBuilder do
  around do |example|
    Time.use_zone('UTC') { example.run }
  end

  let(:now) { Time.utc(2026, 11, 8, 15, 0, 0) }
  let(:stalled_at) { now - 3.days }
  let(:account) { create(:account, scansolo_enabled: true) }
  let(:other_account) { create(:account, scansolo_enabled: true) }
  # RF-07: anchor 2026-11-08 (Sunday) → [2026-11-02T03:00Z, 2026-11-09T03:00Z); W−1 = [2026-10-26T03:00Z, 2026-11-02T03:00Z).
  let(:period) { ScanSolo::Reports::Period.resolve(period: 'week', anchor: Date.new(2026, 11, 8)) }
  let(:em_contato_definition) { ScanSolo::CadenceDefinition.create!(stage: 'em_contato', version: 1, offsets: [24, 48]) }
  let(:proposta_definition) { ScanSolo::CadenceDefinition.create!(stage: 'proposta_enviada', version: 1, offsets: [24, 72]) }
  let(:fixture_content) { 'Meu WhatsApp é +5511988887777 e o e-mail lead.sigiloso@empresa.com.br' }

  def build_report
    described_class.call(account: account, period: period, now: now, source: 'live')
  end

  # A lead with a conversation under AI control, a contact holding PII and one
  # message whose content must never reach the report.
  def opportunity_with(stage:, last_interaction:, target_account: account, created_at: last_interaction || (now - 10.days))
    contact = create(:contact, account: target_account, name: "Lead #{SecureRandom.hex(3)}",
                               email: "#{SecureRandom.hex(4)}@empresa.com.br",
                               phone_number: format('+55119%08d', SecureRandom.random_number(100_000_000)))
    conversation = create(:conversation, account: target_account, contact: contact)
    ScanSolo::ConversationExtension.create!(conversation: conversation, ai_control_state: :ai_active)
    create(:message, account: target_account, conversation: conversation, message_type: :incoming, content: fixture_content)
    ScanSolo::PipelineOpportunity.create!(account: target_account, contact: contact, conversation: conversation, stage: stage,
                                          last_customer_interaction_at: last_interaction, created_at: created_at)
  end

  # Uniform stalled lead with every preloaded association populated: an
  # em_contato enrollment with a future attempt, a quote request and a sent proposal.
  def fully_loaded_stalled_opportunity
    opportunity = opportunity_with(stage: :em_contato, last_interaction: stalled_at)
    enrollment = ScanSolo::CadenceEnrollment.create!(opportunity: opportunity, cadence_definition: em_contato_definition)
    enrollment.attempts.create!(step: 1, cadence_version: 1, template_reference: 'scansolo_follow_up', scheduled_at: now + 1.day)
    quote_request = ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid,
                                                   status: :replied)
    ScanSolo::Proposal.create!(opportunity: opportunity)
                      .versions.create!(status: :sent, quote_request: quote_request, value: 1000, currency: 'BRL')
    opportunity
  end

  def classifier_reason(opportunity, legacy_bulk:)
    preloaded = ScanSolo::PipelineOpportunity.includes(:quote_request, :conversation_extension, proposal: :current_version,
                                                                                                cadence_enrollments: %i[cadence_definition attempts])
                                             .find(opportunity.id)
    commercial_status = ScanSolo::Reports::CommercialStatus.call(quote_request: preloaded.quote_request,
                                                                 current_version: preloaded.proposal&.current_version,
                                                                 escalated: preloaded.escalated_to_commercial?)
    ScanSolo::Reports::StallReason.call(opportunity: preloaded, now: now, commercial_status: commercial_status,
                                        legacy_bulk: legacy_bulk)[:stall_reason]
  end

  def sql_statements(&)
    statements = []
    callback = ->(*, payload) { statements << payload[:sql] unless %w[SCHEMA TRANSACTION].include?(payload[:name]) }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &)
    statements
  end

  describe 'funnel and stalled list (RF-10)' do
    let!(:stalled_new) { opportunity_with(stage: :novo_lead, last_interaction: stalled_at) }
    # Lead handled by the bulk action (CT-07): manual proposal, cancelled post-proposal cadence.
    let!(:legacy_bulk) do
      opportunity_with(stage: :proposta_enviada, last_interaction: stalled_at).tap do |opportunity|
        ScanSolo::CadenceEnrollment.create!(opportunity: opportunity, cadence_definition: proposta_definition, status: :cancelled)
        quote_request = ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid,
                                                       status: :handled_manually, handled_manually_at: now - 4.days)
        ScanSolo::AuditEvent.create!(subject: opportunity, event_type: 'quote_request.handled_manually',
                                     correlation_id: quote_request.correlation_id,
                                     payload: { quote_request_id: quote_request.id, mode: 'bulk', cadence_skipped: 'legacy_bulk' })
      end
    end
    # Handled by the single action: no `cadence_skipped`, so not a legacy lead.
    let!(:single_handled) do
      opportunity_with(stage: :proposta_enviada, last_interaction: stalled_at).tap do |opportunity|
        ScanSolo::CadenceEnrollment.create!(opportunity: opportunity, cadence_definition: proposta_definition, status: :completed)
        quote_request = ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity, correlation_id: SecureRandom.uuid,
                                                       status: :handled_manually, handled_manually_at: now - 4.days)
        ScanSolo::AuditEvent.create!(subject: opportunity, event_type: 'quote_request.handled_manually',
                                     correlation_id: quote_request.correlation_id,
                                     payload: { quote_request_id: quote_request.id, mode: 'single' })
      end
    end
    let!(:never_wrote) { opportunity_with(stage: :em_contato, last_interaction: nil, created_at: now - 48.hours) }
    let!(:qualified) { opportunity_with(stage: :qualificado, last_interaction: stalled_at) }
    let!(:negotiating) { opportunity_with(stage: :negociacao, last_interaction: stalled_at) }

    before do
      opportunity_with(stage: :novo_lead, last_interaction: now - 47.hours)
      opportunity_with(stage: :ganho, last_interaction: now - 30.days)
      opportunity_with(stage: :perdido, last_interaction: now - 30.days)
      opportunity_with(stage: :novo_lead, last_interaction: stalled_at, target_account: other_account)
    end

    it 'matches the RF-10 reference SQL, with 8 stages in enum order and terminal stages never stalled' do
      sql = ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, { a: account.id, as_of: now }])
        SELECT stage,
               COUNT(*) FILTER (WHERE stage NOT IN (6, 7) AND COALESCE(last_customer_interaction_at, created_at) <= CAST(:as_of AS timestamp) - interval '48 hours'),
               COUNT(*)
        FROM scan_solo_pipeline_opportunities WHERE account_id = :a GROUP BY stage
      SQL
      reference = ActiveRecord::Base.connection.select_rows(sql).to_h { |stage, stalled, total| [stage.to_i, [stalled, total]] }
      expected = ScanSolo::PipelineOpportunity.stages.map do |stage, value|
        stalled, total = reference.fetch(value, [0, 0])
        { stage: stage, active: total - stalled, stalled: stalled }
      end

      funnel = build_report[:funnel]

      expect(funnel).to eq(expected)
      expect(funnel.pluck(:stage)).to eq(%w[novo_lead em_contato em_qualificacao qualificado proposta_enviada negociacao ganho perdido])
      expect(funnel.find { |row| row[:stage] == 'novo_lead' }).to eq(stage: 'novo_lead', active: 1, stalled: 1)
      expect(funnel.find { |row| row[:stage] == 'proposta_enviada' }).to eq(stage: 'proposta_enviada', active: 0, stalled: 2)
      expect(funnel.find { |row| row[:stage] == 'ganho' }).to eq(stage: 'ganho', active: 1, stalled: 0)
      expect(funnel.find { |row| row[:stage] == 'perdido' }).to eq(stage: 'perdido', active: 1, stalled: 0)
    end

    it 'lists every stalled opportunity once, with the classifier reason, and sums to the funnel stalled count' do
      report = build_report
      stalled = report[:stalled]
      expected_ids = [stalled_new, never_wrote, qualified, negotiating, legacy_bulk, single_handled].map(&:id)

      expect(stalled.pluck(:opportunity_id)).to match_array(expected_ids)
      expect(stalled.size).to eq(report[:funnel].sum { |row| row[:stalled] })
      stalled.each do |item|
        opportunity = ScanSolo::PipelineOpportunity.find(item[:opportunity_id])
        expect(item[:stall_reason]).to eq(classifier_reason(opportunity, legacy_bulk: opportunity == legacy_bulk))
        expect(item[:suggested_action]).to eq(ScanSolo::Reports::StallReason::SUGGESTED_ACTIONS.fetch(item[:stall_reason]))
      end
    end

    it 'shows the legacy bulk lead with proposta_manual_sem_cadencia and the single-action lead with the normal precedence' do
      stalled = build_report[:stalled].index_by { |item| item[:opportunity_id] }

      expect(stalled.fetch(legacy_bulk.id)).to include(stage: 'proposta_enviada', commercial_status: 'proposta_enviada_manual',
                                                       stall_reason: 'proposta_manual_sem_cadencia')
      expect(stalled.fetch(single_handled.id)).to include(commercial_status: 'proposta_enviada_manual',
                                                          stall_reason: 'cadencia_concluida_sem_resposta')
      expect(stalled.fetch(qualified.id)).to include(commercial_status: 'nao_encaminhado', stall_reason: 'qualificado_sem_encaminhamento')
      expect(stalled.fetch(negotiating.id)[:stall_reason]).to eq('outro')
    end

    it 'returns exactly the CT-01 item fields' do
      item = build_report[:stalled].find { |entry| entry[:opportunity_id] == never_wrote.id }

      expect(item).to eq(
        opportunity_id: never_wrote.id,
        contact_name: never_wrote.contact.name,
        stage: 'em_contato',
        last_customer_interaction_at: nil,
        created_at: '2026-11-06T12:00:00-03:00',
        commercial_status: 'nao_encaminhado',
        stall_reason: 'sem_followup_agendado',
        suggested_action: 'SCANSOLO.REPORTS.SUGGESTED_ACTIONS.SEM_FOLLOWUP_AGENDADO'
      )
    end

    it 'never serializes phone, e-mail nor message content (RNF-01)' do
      json = build_report.to_json

      expect(json).not_to include('@')
      expect(json).not_to include('+55')
      expect(json).not_to include(fixture_content)
      expect(json).not_to include('sigiloso')
    end

    it 'only reads from the database' do
      statements = sql_statements { build_report }

      expect(statements).not_to be_empty
      expect(statements).to all(match(/\A\s*SELECT/i))
    end
  end

  # Escalação comercial RF-17: the stalled item reads the escalation mark.
  it 'reports escalado_wa for a stalled escalated opportunity' do
    escalated = opportunity_with(stage: :qualificado, last_interaction: stalled_at)
    escalated.update!(escalated_to_commercial_at: stalled_at, escalation_reason: 'negociacao')

    item = build_report[:stalled].find { |entry| entry[:opportunity_id] == escalated.id }

    expect(item).to include(commercial_status: 'escalado_wa')
  end

  it 'returns the CT-01 envelope with ISO 8601 São Paulo instants' do
    report = build_report

    expect(report.keys).to eq(%i[period anchor timezone starts_at ends_at source generated_at as_of summary previous funnel stalled])
    expect(report).to include(period: 'week', anchor: '2026-11-08', timezone: 'America/Sao_Paulo',
                              starts_at: '2026-11-02T00:00:00-03:00', ends_at: '2026-11-09T00:00:00-03:00', source: 'live',
                              generated_at: '2026-11-08T12:00:00-03:00', as_of: '2026-11-08T12:00:00-03:00', stalled: [])
    expect(report[:previous]).to include(starts_at: '2026-10-26T00:00:00-03:00', ends_at: '2026-11-02T00:00:00-03:00')
    expect(report[:summary].keys).to eq(report[:previous][:summary].keys)
  end

  it 'reports the previous period summary (RF-09)' do
    3.times { opportunity_with(stage: :novo_lead, last_interaction: nil, created_at: Time.utc(2026, 11, 4, 12)) }
    5.times { opportunity_with(stage: :novo_lead, last_interaction: nil, created_at: Time.utc(2026, 10, 28, 12)) }

    report = build_report

    expect(report[:summary][:new_leads][:total]).to eq(3)
    expect(report[:previous][:summary][:new_leads][:total]).to eq(5)
  end

  it 'runs the same number of queries for 3 and 30 stalled opportunities (RNF-02)' do
    3.times { fully_loaded_stalled_opportunity }
    with_three = sql_statements { expect(build_report[:stalled].size).to eq(3) }.size

    27.times { fully_loaded_stalled_opportunity }
    with_thirty = sql_statements { expect(build_report[:stalled].size).to eq(30) }.size

    expect(with_thirty).to eq(with_three)
  end
end
