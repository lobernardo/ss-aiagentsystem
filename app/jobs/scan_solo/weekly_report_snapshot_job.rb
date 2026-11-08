# RF-13/CT-05/CT-06: registered in config/schedule.yml for Monday 06:00
# America/Sao_Paulo. Freezes the previous complete week (Monday → Sunday in SP)
# of every account with ScanSolo enabled as the CT-01 body for period=week. One
# row per (account, week_start): a 2nd run for the same week overwrites the
# payload (upsert, the last run wins).
class ScanSolo::WeeklyReportSnapshotJob < ApplicationJob
  OVERWRITE_SQL = Arel.sql('payload = EXCLUDED.payload, generated_at = EXCLUDED.generated_at, updated_at = EXCLUDED.updated_at')

  queue_as :scheduled_jobs

  def perform
    now = Time.current
    week_start = now.in_time_zone(ScanSolo::Reports::Period::TIMEZONE).prev_week(:monday).to_date
    period = ScanSolo::Reports::Period.resolve(period: 'week', anchor: week_start)

    Account.scansolo_enabled.find_each do |account|
      payload = ScanSolo::Reports::ReportBuilder.call(account: account, period: period, now: now, source: 'snapshot')
      ScanSolo::ReportSnapshot.upsert( # rubocop:disable Rails/SkipsModelValidations
        { account_id: account.id, week_start: week_start, payload: payload, generated_at: now, created_at: now, updated_at: now },
        unique_by: %i[account_id week_start], on_duplicate: OVERWRITE_SQL, record_timestamps: false
      )
    end
  end
end
