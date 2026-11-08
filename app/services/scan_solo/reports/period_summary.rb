# Relatórios RF-08/RF-09: the period indicators of the CT-01 `summary`, one
# read-only query per indicator (fixed query count, RNF-02). `range` is the
# half-open UTC interval `starts_at...ends_at` from ScanSolo::Reports::Period;
# the caller reuses this object for the previous period (RF-09). Every group is
# returned with its full key set (zeros for empty groups). Only counts,
# timestamps and normalized reasons are read: never message content or the raw
# `failure_reason` (RNF-01). Only SELECTs are executed (RNF-03).
class ScanSolo::Reports::PeriodSummary
  LEAD_SOURCE_MISSING = 'nao_informada'.freeze
  REASON_MISSING = 'nao_informado'.freeze
  REASON_STATUSES = %w[suppressed failed].freeze
  CADENCE_RESULTS = %w[scheduled dispatched sent skipped failed cancelled].freeze
  OPPORTUNITY_SUBJECT = 'ScanSolo::PipelineOpportunity'.freeze

  # `failure_reason` up to the first ": " (exclusive), the whole value without
  # it, or `nao_informado` when null.
  NORMALIZED_REASON_SQL = <<~SQL.squish.freeze
    CASE
      WHEN scan_solo_ai_turns.failure_reason IS NULL THEN '#{REASON_MISSING}'
      WHEN position(': ' IN scan_solo_ai_turns.failure_reason) > 0
        THEN left(scan_solo_ai_turns.failure_reason, position(': ' IN scan_solo_ai_turns.failure_reason) - 1)
      ELSE scan_solo_ai_turns.failure_reason
    END
  SQL

  # Cohort = opportunities created in the period. I = first non-private
  # incoming message of the conversation; R = first non-private outgoing
  # message after I. Only opportunities with R are in the sample.
  FIRST_RESPONSE_SQL = <<~SQL.squish.freeze
    SELECT COUNT(*) AS responded,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY minutes) AS median,
           percentile_cont(0.9) WITHIN GROUP (ORDER BY minutes) AS p90
    FROM (
      SELECT EXTRACT(EPOCH FROM (first_response.created_at - first_inbound.created_at)) / 60.0 AS minutes
      FROM scan_solo_pipeline_opportunities opportunities
      CROSS JOIN LATERAL (
        SELECT MIN(messages.created_at) AS created_at FROM messages
        WHERE messages.conversation_id = opportunities.conversation_id
          AND messages.message_type = 0 AND messages.private = false
      ) first_inbound
      CROSS JOIN LATERAL (
        SELECT MIN(messages.created_at) AS created_at FROM messages
        WHERE messages.conversation_id = opportunities.conversation_id
          AND messages.message_type = 1 AND messages.private = false
          AND messages.created_at > first_inbound.created_at
      ) first_response
      WHERE opportunities.account_id = :account_id
        AND opportunities.created_at >= :starts_at AND opportunities.created_at < :ends_at
        AND first_response.created_at IS NOT NULL
    ) samples
  SQL

  # Distinct opportunities that entered `qualificado` in the period: stage
  # events plus manual leads created directly in `qualificado` (no stage event).
  QUALIFIED_SQL = <<~SQL.squish.freeze
    SELECT COUNT(DISTINCT opportunity_id) FROM (
      SELECT events.opportunity_id
      FROM scan_solo_pipeline_stage_events events
      JOIN scan_solo_pipeline_opportunities opportunities ON opportunities.id = events.opportunity_id
      WHERE opportunities.account_id = :account_id AND events.to_stage = 'qualificado'
        AND events.created_at >= :starts_at AND events.created_at < :ends_at
      UNION
      SELECT audits.subject_id
      FROM scan_solo_audit_events audits
      JOIN scan_solo_pipeline_opportunities opportunities ON opportunities.id = audits.subject_id
      WHERE audits.subject_type = '#{OPPORTUNITY_SUBJECT}' AND opportunities.account_id = :account_id
        AND audits.event_type = 'pipeline.opportunity_created'
        AND audits.payload->>'source' = 'manual' AND audits.payload->>'initial_stage' = 'qualificado'
        AND audits.created_at >= :starts_at AND audits.created_at < :ends_at
    ) qualified
  SQL

  def self.call(account:, range:)
    new(account: account, range: range).call
  end

  def initialize(account:, range:)
    @account = account
    @range = range
  end

  def call
    {
      new_leads: new_leads,
      **responses,
      ai_turns: { by_status: ai_turns_by_status, by_reason: ai_turns_by_reason },
      inbound_without_turn: { total: inbound_without_turn },
      cadence_attempts: { by_result: cadence_attempts_by_result, by_block_reason: cadence_attempts_by_block_reason },
      qualified: { total: select_value(QUALIFIED_SQL) },
      forwarded: { total: ScanSolo::QuoteRequest.where(account_id: @account.id, sent_at: @range).count },
      proposals: { by_status: proposals_by_status }
    }
  end

  private

  def opportunities
    ScanSolo::PipelineOpportunity.where(account_id: @account.id)
  end

  def new_leads
    counts = opportunities.where(created_at: @range).group(Arel.sql("COALESCE(lead_source, '#{LEAD_SOURCE_MISSING}')")).count
    by_source = full_keys(ScanSolo::PipelineOpportunity::LEAD_SOURCES + [LEAD_SOURCE_MISSING], counts)

    { total: by_source.values.sum, by_source: by_source }
  end

  def responses
    row = ActiveRecord::Base.connection.select_one(sanitize(FIRST_RESPONSE_SQL))

    {
      responded: { total: row['responded'].to_i },
      first_response_minutes: { median: row['median']&.to_f, p90: row['p90']&.to_f }
    }
  end

  def ai_turns
    ScanSolo::AiTurn.joins(:conversation).where(conversations: { account_id: @account.id }, created_at: @range)
  end

  def ai_turns_by_status
    full_keys(ScanSolo::AiTurn.invocation_statuses.keys, ai_turns.group(:invocation_status).count)
  end

  def ai_turns_by_reason
    ai_turns.where(invocation_status: REASON_STATUSES)
            .group(:invocation_status, Arel.sql(NORMALIZED_REASON_SQL))
            .order(:invocation_status, Arel.sql(NORMALIZED_REASON_SQL))
            .pluck(:invocation_status, Arel.sql(NORMALIZED_REASON_SQL), Arel.sql('COUNT(*)'))
            .map { |status, reason, count| { status: status, reason: reason, count: count } }
  end

  def inbound_without_turn
    Message.where(message_type: :incoming, private: false, created_at: @range)
           .where(conversation_id: opportunities.select(:conversation_id))
           .where.not(ScanSolo::AiTurn.where('scan_solo_ai_turns.message_id = messages.id').arel.exists)
           .count
  end

  def cadence_attempts
    ScanSolo::CadenceAttempt.joins(enrollment: :opportunity).where(scan_solo_pipeline_opportunities: { account_id: @account.id })
  end

  def cadence_attempts_by_result
    full_keys(CADENCE_RESULTS, cadence_attempts.where(scheduled_at: @range).group(:result).count)
  end

  def cadence_attempts_by_block_reason
    cadence_attempts.where.not(last_block_reason: nil).where(last_checked_at: @range)
                    .group(:last_block_reason).order(:last_block_reason).count
                    .map { |reason, count| { reason: reason, count: count } }
  end

  def proposals_by_status
    versions = ScanSolo::ProposalVersion.joins(proposal: :opportunity)
                                        .where(scan_solo_pipeline_opportunities: { account_id: @account.id }, created_at: @range)
    full_keys(ScanSolo::ProposalVersion.statuses.keys, versions.group(:status).count)
  end

  def full_keys(keys, counts)
    keys.index_with { |key| counts.fetch(key, 0) }.symbolize_keys
  end

  def select_value(sql)
    ActiveRecord::Base.connection.select_value(sanitize(sql)).to_i
  end

  def sanitize(sql)
    ActiveRecord::Base.sanitize_sql_array([sql, { account_id: @account.id, starts_at: @range.begin, ends_at: @range.end }])
  end
end
