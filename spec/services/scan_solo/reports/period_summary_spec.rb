# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScanSolo::Reports::PeriodSummary do
  around do |example|
    Time.use_zone('UTC') { example.run }
  end

  let(:account) { create(:account, scansolo_enabled: true) }
  let(:other_account) { create(:account, scansolo_enabled: true) }
  # RF-07: anchor 2026-11-08 (Sunday) → [2026-11-02T03:00Z, 2026-11-09T03:00Z).
  let(:period) { ScanSolo::Reports::Period.resolve(period: 'week', anchor: Date.new(2026, 11, 8)) }
  let(:starts_at) { Time.utc(2026, 11, 2, 3, 0, 0) }
  let(:ends_at) { Time.utc(2026, 11, 9, 3, 0, 0) }
  let(:inside) { Time.utc(2026, 11, 4, 12, 0, 0) }
  let(:before_period) { Time.utc(2026, 10, 28, 12, 0, 0) }
  let(:after_period) { Time.utc(2026, 11, 10, 12, 0, 0) }

  def summary
    described_class.call(account: account, range: period.range)
  end

  # Runs an RF-08 reference query on the same test database.
  def reference(sql)
    bound = ActiveRecord::Base.sanitize_sql_array([sql, { a: account.id, s: starts_at, e: ends_at }])
    ActiveRecord::Base.connection.select_rows(bound)
  end

  def opportunity_at(created_at, target_account: account, **attributes)
    contact = create(:contact, account: target_account)
    conversation = create(:conversation, account: target_account, contact: contact)
    ScanSolo::PipelineOpportunity.create!(account: target_account, contact: contact, conversation: conversation,
                                          created_at: created_at, **attributes)
  end

  def message_at(opportunity, message_type, created_at, **attributes)
    create(:message, account: opportunity.account, conversation: opportunity.conversation, message_type: message_type,
                     created_at: created_at, **attributes)
  end

  def turn_for(message, status, created_at: message.created_at, failure_reason: nil)
    ScanSolo::AiTurn.create!(message: message, conversation: message.conversation, correlation_id: SecureRandom.uuid,
                             invocation_status: status, failure_reason: failure_reason, created_at: created_at)
  end

  it 'returns every key with zeros and null percentiles for an empty period' do
    expect(summary).to eq(
      new_leads: { total: 0, by_source: { website: 0, manual: 0, nao_informada: 0 } },
      responded: { total: 0 },
      first_response_minutes: { median: nil, p90: nil },
      ai_turns: { by_status: { pending: 0, suppressed: 0, succeeded: 0, failed: 0 }, by_reason: [] },
      inbound_without_turn: { total: 0 },
      cadence_attempts: { by_result: { scheduled: 0, dispatched: 0, sent: 0, skipped: 0, failed: 0, cancelled: 0 }, by_block_reason: [] },
      qualified: { total: 0 },
      forwarded: { total: 0 },
      proposals: { by_status: { generating: 0, generated: 0, approved: 0, sent: 0, failed: 0, awaiting_approval: 0, rejected: 0 } }
    )
  end

  describe 'new_leads' do
    before do
      opportunity_at(inside, lead_source: 'website')
      opportunity_at(inside, lead_source: 'manual')
      opportunity_at(inside, lead_source: nil)
      opportunity_at(Time.utc(2026, 11, 9, 2, 59, 59), lead_source: 'website') # Sunday 23:59:59 SP
      opportunity_at(ends_at, lead_source: 'website') # Monday 00:00:00 SP
      opportunity_at(Time.utc(2026, 11, 2, 2, 59, 59), lead_source: 'website') # previous Sunday 23:59:59 SP
      opportunity_at(inside, target_account: other_account, lead_source: 'website')
    end

    it 'counts the period leads by source, respecting the Sunday 23:59:59 SP boundary' do
      expect(summary[:new_leads]).to eq(total: 4, by_source: { website: 2, manual: 1, nao_informada: 1 })
    end

    it 'matches the RF-08 reference query' do
      rows = reference(<<~SQL.squish)
        SELECT COALESCE(lead_source,'nao_informada'), COUNT(*) FROM scan_solo_pipeline_opportunities
        WHERE account_id=:a AND created_at >= :s AND created_at < :e GROUP BY 1
      SQL

      expect(summary[:new_leads][:by_source].transform_keys(&:to_s).reject { |_, count| count.zero? }).to eq(rows.to_h)
      expect(summary[:new_leads][:total]).to eq(rows.sum { |_, count| count })
    end
  end

  describe 'responded and first_response_minutes' do
    let(:first_inbound) { inside }

    before do
      # AI reply 10 min after the first incoming; a later incoming does not move I.
      ai_replied = opportunity_at(inside - 1.hour)
      message_at(ai_replied, :incoming, first_inbound)
      message_at(ai_replied, :incoming, first_inbound + 5.minutes)
      message_at(ai_replied, :outgoing, first_inbound + 10.minutes)

      # Answered only by a cadence template, 30 min later; the private note in between does not count.
      cadence_only = opportunity_at(inside - 1.hour)
      message_at(cadence_only, :incoming, first_inbound)
      message_at(cadence_only, :outgoing, first_inbound + 1.minute, private: true)
      message_at(cadence_only, :outgoing, first_inbound + 30.minutes, additional_attributes: { 'scansolo_origin' => 'cadence' })

      # Manual lead that never wrote: outside responded and outside the sample.
      manual = opportunity_at(inside, lead_source: 'manual')
      message_at(manual, :outgoing, inside + 1.minute, additional_attributes: { 'scansolo_origin' => 'manual_lead' })

      # Created the week before, answered this week: outside the cohort.
      previous_week = opportunity_at(before_period)
      message_at(previous_week, :incoming, inside)
      message_at(previous_week, :outgoing, inside + 2.minutes)

      # Outgoing only before the first incoming, and an unanswered lead.
      answered_before = opportunity_at(inside)
      message_at(answered_before, :outgoing, inside)
      message_at(answered_before, :incoming, inside + 1.minute)
      unanswered = opportunity_at(inside)
      message_at(unanswered, :incoming, inside)
    end

    it 'counts the cohort leads answered after their first incoming, including the cadence-only one' do
      expect(summary[:responded]).to eq(total: 2)
    end

    it 'returns the median and p90 in minutes of the responded sample' do
      expect(summary[:first_response_minutes]).to eq(median: 20.0, p90: 28.0)
    end

    it 'matches the RF-08 reference queries' do
      rows = reference(<<~SQL.squish)
        SELECT COUNT(*),
               percentile_cont(0.5) WITHIN GROUP (ORDER BY minutes),
               percentile_cont(0.9) WITHIN GROUP (ORDER BY minutes)
        FROM (
          SELECT EXTRACT(EPOCH FROM (
                   (SELECT MIN(r.created_at) FROM messages r
                    WHERE r.conversation_id = o.conversation_id AND r.message_type = 1 AND r.private = false
                      AND r.created_at > i.first_at)
                   - i.first_at)) / 60 AS minutes
          FROM scan_solo_pipeline_opportunities o
          JOIN (SELECT conversation_id, MIN(created_at) AS first_at FROM messages
                WHERE message_type = 0 AND private = false GROUP BY conversation_id) i ON i.conversation_id = o.conversation_id
          WHERE o.account_id = :a AND o.created_at >= :s AND o.created_at < :e
            AND EXISTS (SELECT 1 FROM messages r WHERE r.conversation_id = o.conversation_id AND r.message_type = 1
                          AND r.private = false AND r.created_at > i.first_at)
        ) sample
      SQL
      count, median, p90 = rows.first

      expect(summary[:responded][:total]).to eq(count)
      expect(summary[:first_response_minutes]).to eq(median: median.to_f, p90: p90.to_f)
    end
  end

  describe 'ai_turns' do
    before do
      opportunity = opportunity_at(inside)
      other = opportunity_at(inside, target_account: other_account)
      turn_for(message_at(opportunity, :incoming, inside), :succeeded)
      turn_for(message_at(opportunity, :incoming, inside), :pending)
      turn_for(message_at(opportunity, :incoming, inside), :suppressed, failure_reason: 'duplicate_message')
      turn_for(message_at(opportunity, :incoming, inside), :failed, failure_reason: 'Faraday::TimeoutError: [redacted] secret')
      turn_for(message_at(opportunity, :incoming, inside), :failed, failure_reason: 'Faraday::TimeoutError: another detail')
      turn_for(message_at(opportunity, :incoming, inside), :failed)
      turn_for(message_at(opportunity, :incoming, before_period), :failed, failure_reason: 'stale_pending')
      turn_for(message_at(other, :incoming, inside), :failed, failure_reason: 'stale_pending')
    end

    it 'counts the period turns of the account by status' do
      expect(summary[:ai_turns][:by_status]).to eq(pending: 1, suppressed: 1, succeeded: 1, failed: 3)
    end

    it 'groups suppressed and failed turns by normalized reason, never exposing the raw failure_reason' do
      expect(summary[:ai_turns][:by_reason]).to eq(
        [
          { status: 'suppressed', reason: 'duplicate_message', count: 1 },
          { status: 'failed', reason: 'Faraday::TimeoutError', count: 2 },
          { status: 'failed', reason: 'nao_informado', count: 1 }
        ]
      )
      expect(summary.to_s).not_to include('secret', 'another detail')
    end

    it 'matches the RF-08 reference queries' do
      by_status = reference(<<~SQL.squish)
        SELECT t.invocation_status, COUNT(*) FROM scan_solo_ai_turns t JOIN conversations c ON c.id = t.conversation_id
        WHERE c.account_id = :a AND t.created_at >= :s AND t.created_at < :e GROUP BY 1
      SQL
      by_reason = reference(<<~SQL.squish)
        SELECT t.invocation_status,
               CASE WHEN t.failure_reason IS NULL THEN 'nao_informado'
                    WHEN strpos(t.failure_reason, ': ') = 0 THEN t.failure_reason
                    ELSE split_part(t.failure_reason, ': ', 1) END,
               COUNT(*)
        FROM scan_solo_ai_turns t JOIN conversations c ON c.id = t.conversation_id
        WHERE c.account_id = :a AND t.created_at >= :s AND t.created_at < :e AND t.invocation_status IN (1, 3)
        GROUP BY 1, 2
      SQL
      statuses = ScanSolo::AiTurn.invocation_statuses.invert

      expect(summary[:ai_turns][:by_status].transform_keys(&:to_s).reject { |_, count| count.zero? })
        .to eq(by_status.to_h.transform_keys { |status| statuses.fetch(status) })
      expect(summary[:ai_turns][:by_reason]).to match_array(
        by_reason.map { |status, reason, count| { status: statuses.fetch(status), reason: reason, count: count } }
      )
    end
  end

  describe 'inbound_without_turn' do
    before do
      opportunity = opportunity_at(inside)
      turn_for(message_at(opportunity, :incoming, inside), :succeeded)
      message_at(opportunity, :incoming, inside + 1.minute)
      message_at(opportunity, :incoming, inside + 2.minutes, private: true)
      message_at(opportunity, :outgoing, inside + 3.minutes)
      message_at(opportunity, :incoming, after_period)
      message_at(opportunity_at(inside, target_account: other_account), :incoming, inside)
      create(:message, account: account, message_type: :incoming, created_at: inside) # conversation without opportunity
    end

    it 'counts the period incoming messages of opportunity conversations that got no AI turn' do
      expect(summary[:inbound_without_turn]).to eq(total: 1)
    end

    it 'matches the RF-08 reference query' do
      rows = reference(<<~SQL.squish)
        SELECT COUNT(*) FROM messages m
        WHERE m.message_type = 0 AND m.private = false AND m.created_at >= :s AND m.created_at < :e
          AND m.conversation_id IN (SELECT conversation_id FROM scan_solo_pipeline_opportunities WHERE account_id = :a)
          AND m.id NOT IN (SELECT message_id FROM scan_solo_ai_turns)
      SQL

      expect(summary[:inbound_without_turn][:total]).to eq(rows.first.first)
    end
  end

  describe 'cadence_attempts' do
    before do
      definition = ScanSolo::CadenceDefinition.create!(stage: 'em_contato', version: 1, offsets: [24, 48])
      enrollment = ScanSolo::CadenceEnrollment.create!(opportunity: opportunity_at(inside), cadence_definition: definition, status: :active)
      other_enrollment = ScanSolo::CadenceEnrollment.create!(opportunity: opportunity_at(inside, target_account: other_account),
                                                             cadence_definition: definition, status: :active)
      attempts = [
        [enrollment, :sent, inside, nil, nil],
        [enrollment, :scheduled, inside, 'template_missing', inside],
        [enrollment, :scheduled, inside, 'params_mismatch', inside],
        [enrollment, :failed, inside, 'template_missing', inside],
        [enrollment, :dispatched, inside, 'template_missing', before_period], # checked outside the period
        [enrollment, :cancelled, after_period, 'template_missing', inside], # scheduled outside, checked inside
        [other_enrollment, :sent, inside, 'template_missing', inside]
      ]
      attempts.each_with_index do |(owner, result, scheduled_at, block_reason, checked_at), index|
        ScanSolo::CadenceAttempt.create!(enrollment: owner, step: index + 1, cadence_version: 1, template_reference: "t#{index}",
                                         result: result, scheduled_at: scheduled_at, last_block_reason: block_reason,
                                         last_checked_at: checked_at)
      end
    end

    it 'counts the attempts scheduled in the period by result' do
      expect(summary[:cadence_attempts][:by_result]).to eq(scheduled: 2, dispatched: 1, sent: 1, skipped: 0, failed: 1, cancelled: 0)
    end

    it 'counts the block reasons checked in the period' do
      expect(summary[:cadence_attempts][:by_block_reason]).to eq(
        [{ reason: 'params_mismatch', count: 1 }, { reason: 'template_missing', count: 3 }]
      )
    end

    it 'matches the RF-08 reference queries' do
      join = 'FROM scan_solo_cadence_attempts t JOIN scan_solo_cadence_enrollments en ON en.id = t.enrollment_id ' \
             'JOIN scan_solo_pipeline_opportunities o ON o.id = en.opportunity_id WHERE o.account_id = :a'
      by_result = reference("SELECT t.result, COUNT(*) #{join} AND t.scheduled_at >= :s AND t.scheduled_at < :e GROUP BY 1")
      by_block = reference("SELECT t.last_block_reason, COUNT(*) #{join} AND t.last_block_reason IS NOT NULL " \
                           'AND t.last_checked_at >= :s AND t.last_checked_at < :e GROUP BY 1')
      results = ScanSolo::CadenceAttempt.results.invert

      expect(summary[:cadence_attempts][:by_result].transform_keys(&:to_s).reject { |_, count| count.zero? })
        .to eq(by_result.to_h.transform_keys { |result| results.fetch(result) })
      expect(summary[:cadence_attempts][:by_block_reason]).to match_array(by_block.map { |reason, count| { reason: reason, count: count } })
    end
  end

  describe 'qualified' do
    def stage_event(opportunity, created_at)
      ScanSolo::PipelineStageEvent.create!(opportunity: opportunity, from_stage: 'em_qualificacao', to_stage: 'qualificado',
                                           created_at: created_at)
    end

    def manual_creation(opportunity, initial_stage, created_at)
      ScanSolo::AuditEvent.create!(subject: opportunity, event_type: 'pipeline.opportunity_created', correlation_id: SecureRandom.uuid,
                                   payload: { source: 'manual', initial_stage: initial_stage }, created_at: created_at)
    end

    before do
      twice = opportunity_at(before_period, stage: :qualificado)
      stage_event(twice, inside)
      stage_event(twice, inside + 1.hour)

      manual_lead = opportunity_at(inside, stage: :qualificado, lead_source: 'manual')
      manual_creation(manual_lead, 'qualificado', inside)

      both = opportunity_at(inside, stage: :qualificado, lead_source: 'manual')
      manual_creation(both, 'qualificado', inside)
      stage_event(both, inside + 1.hour)

      stage_event(opportunity_at(before_period, stage: :qualificado), before_period)
      manual_creation(opportunity_at(inside, stage: :novo_lead, lead_source: 'manual'), 'novo_lead', inside)
      stage_event(opportunity_at(inside, target_account: other_account, stage: :qualificado), inside)
    end

    it 'counts distinct opportunities from stage events and manual leads created in qualificado' do
      expect(summary[:qualified]).to eq(total: 3)
    end

    it 'matches the RF-08 reference query' do
      rows = reference(<<~SQL.squish)
        SELECT COUNT(*) FROM scan_solo_pipeline_opportunities o
        WHERE o.account_id = :a AND (
          EXISTS (SELECT 1 FROM scan_solo_pipeline_stage_events e WHERE e.opportunity_id = o.id AND e.to_stage = 'qualificado'
                    AND e.created_at >= :s AND e.created_at < :e)
          OR EXISTS (SELECT 1 FROM scan_solo_audit_events ae
                     WHERE ae.subject_type = 'ScanSolo::PipelineOpportunity' AND ae.subject_id = o.id
                       AND ae.event_type = 'pipeline.opportunity_created' AND ae.payload->>'source' = 'manual'
                       AND ae.payload->>'initial_stage' = 'qualificado' AND ae.created_at >= :s AND ae.created_at < :e))
      SQL

      expect(summary[:qualified][:total]).to eq(rows.first.first)
    end
  end

  describe 'forwarded' do
    before do
      [inside, Time.utc(2026, 11, 9, 2, 59, 59), ends_at, before_period, nil].each do |sent_at|
        ScanSolo::QuoteRequest.create!(account: account, opportunity: opportunity_at(inside), correlation_id: SecureRandom.uuid,
                                       sent_at: sent_at)
      end
      other = opportunity_at(inside, target_account: other_account)
      ScanSolo::QuoteRequest.create!(account: other_account, opportunity: other, correlation_id: SecureRandom.uuid, sent_at: inside)
    end

    it 'counts the requests sent to the commercial contact in the period' do
      expect(summary[:forwarded]).to eq(total: 2)
    end

    it 'matches the RF-08 reference query' do
      rows = reference('SELECT COUNT(*) FROM scan_solo_quote_requests WHERE account_id=:a AND sent_at >= :s AND sent_at < :e')

      expect(summary[:forwarded][:total]).to eq(rows.first.first)
    end
  end

  describe 'proposals' do
    before do
      proposal = ScanSolo::Proposal.create!(opportunity: opportunity_at(before_period))
      %i[failed rejected sent awaiting_approval].each { |status| proposal.versions.create!(status: status, created_at: inside) }
      proposal.versions.create!(status: :sent, created_at: before_period)
      other = ScanSolo::Proposal.create!(opportunity: opportunity_at(inside, target_account: other_account))
      other.versions.create!(status: :sent, created_at: inside)
    end

    it 'counts the period proposal versions of the account by current status' do
      expect(summary[:proposals][:by_status]).to eq(
        generating: 0, generated: 0, approved: 0, sent: 1, failed: 1, awaiting_approval: 1, rejected: 1
      )
    end

    it 'matches the RF-08 reference query' do
      rows = reference(<<~SQL.squish)
        SELECT v.status, COUNT(*) FROM scan_solo_proposal_versions v
        JOIN scan_solo_proposals p ON p.id = v.proposal_id JOIN scan_solo_pipeline_opportunities o ON o.id = p.opportunity_id
        WHERE o.account_id = :a AND v.created_at >= :s AND v.created_at < :e GROUP BY 1
      SQL
      statuses = ScanSolo::ProposalVersion.statuses.invert

      expect(summary[:proposals][:by_status].transform_keys(&:to_s).reject { |_, count| count.zero? })
        .to eq(rows.to_h.transform_keys { |status| statuses.fetch(status) })
    end
  end

  it 'only runs SELECT statements and never reads message content (RNF-01/RNF-03)' do
    opportunity = opportunity_at(inside)
    message_at(opportunity, :incoming, inside, content: 'conteudo sigiloso do lead')
    message_at(opportunity, :outgoing, inside + 3.minutes, content: 'resposta sigilosa')
    statements = []
    callback = ->(*, payload) { statements << payload[:sql] unless payload[:name] == 'SCHEMA' }

    result = ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { summary }

    expect(statements).to all(match(/\A\s*SELECT/i))
    expect(statements.join).not_to match(/messages\.content|\bcontent\b/)
    expect(result.to_s).not_to include('sigilos')
    expect(result[:responded]).to eq(total: 1)
  end
end
