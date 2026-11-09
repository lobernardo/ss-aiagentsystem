# Relatórios CT-01 (RF-09/RF-10/RF-14): assembles the report body as a plain
# Hash, rendered as-is by the reports endpoint and stored byte for byte as the
# weekly snapshot payload. `summary`/`previous.summary` come from
# PeriodSummary; the funnel and the stalled list reflect the state at `now`
# (`as_of`), not the period. The stalled list is built from preloaded
# associations plus 1 audit query, so the query count does not grow with the
# number of stalled opportunities (RNF-02). Read-only, and only ids, names,
# stages, timestamps and classifier values leave this object: no phone,
# e-mail or message content (RNF-01).
class ScanSolo::Reports::ReportBuilder
  LEGACY_BULK_EVENT = 'quote_request.handled_manually'.freeze
  LEGACY_BULK_SKIP = 'legacy_bulk'.freeze

  def self.call(account:, period:, now: Time.current, source: 'live')
    new(account: account, period: period, now: now, source: source).call
  end

  def initialize(account:, period:, now:, source:)
    @account = account
    @period = period
    @now = now
    @source = source
  end

  def call
    previous = period.previous

    {
      period: period.period,
      anchor: period.anchor.iso8601,
      timezone: ScanSolo::Reports::Period::TIMEZONE,
      **bounds(period),
      source: source,
      generated_at: local_iso8601(now),
      as_of: local_iso8601(now),
      summary: ScanSolo::Reports::PeriodSummary.call(account: account, range: period.range),
      previous: {
        **bounds(previous),
        summary: ScanSolo::Reports::PeriodSummary.call(account: account, range: previous.range)
      },
      funnel: funnel,
      stalled: stalled
    }
  end

  private

  attr_reader :account, :period, :now, :source

  def bounds(report_period)
    { starts_at: report_period.starts_at.iso8601, ends_at: report_period.ends_at.iso8601 }
  end

  def opportunities
    ScanSolo::PipelineOpportunity.where(account_id: account.id)
  end

  def stalled_scope
    ScanSolo::Pipeline::OpportunityQuery.stalled_scope(opportunities, as_of: now)
  end

  def funnel
    totals = opportunities.group(:stage).count
    stalled_counts = stalled_scope.group(:stage).count

    ScanSolo::PipelineOpportunity.stages.keys.map do |stage|
      stalled_count = stalled_counts.fetch(stage, 0)
      { stage: stage, active: totals.fetch(stage, 0) - stalled_count, stalled: stalled_count }
    end
  end

  def stalled
    records = stalled_scope.includes(:contact, :quote_request, :conversation_extension, proposal: :current_version,
                                                                                        cadence_enrollments: %i[cadence_definition attempts])
                           .order(Arel.sql("#{ScanSolo::Pipeline::OpportunityQuery::LAST_ACTIVITY_SQL} ASC"), :id)
                           .to_a
    legacy_bulk_ids = legacy_bulk_ids(records.map(&:id))

    records.map { |opportunity| stalled_item(opportunity, legacy_bulk_ids.include?(opportunity.id)) }
  end

  # The opportunities whose post-proposal cadence was cancelled by the bulk
  # action (CT-07), in a single query for the whole list.
  def legacy_bulk_ids(ids)
    ScanSolo::AuditEvent.where(subject_type: ScanSolo::PipelineOpportunity.name, subject_id: ids, event_type: LEGACY_BULK_EVENT)
                        .where("payload->>'cadence_skipped' = ?", LEGACY_BULK_SKIP)
                        .distinct
                        .pluck(:subject_id)
                        .to_set
  end

  def stalled_item(opportunity, legacy_bulk)
    commercial_status = ScanSolo::Reports::CommercialStatus.call(quote_request: opportunity.quote_request,
                                                                 current_version: opportunity.proposal&.current_version,
                                                                 escalated: opportunity.escalated_to_commercial?)
    reason = ScanSolo::Reports::StallReason.call(opportunity: opportunity, now: now, commercial_status: commercial_status,
                                                 legacy_bulk: legacy_bulk)

    {
      opportunity_id: opportunity.id,
      contact_name: opportunity.contact.name,
      stage: opportunity.stage,
      last_customer_interaction_at: local_iso8601(opportunity.last_customer_interaction_at),
      created_at: local_iso8601(opportunity.created_at),
      commercial_status: commercial_status,
      **reason
    }
  end

  def local_iso8601(time)
    time&.in_time_zone(ScanSolo::Reports::Period::TIMEZONE)&.iso8601
  end
end
