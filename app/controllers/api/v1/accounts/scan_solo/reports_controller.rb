# RF-11/RF-12/RF-14 / CT-01: read-only Relatórios report. A closed week with a
# stored snapshot is served from the snapshot payload; anything else (current
# week, any month, closed week without snapshot) is computed live. Never writes.
class Api::V1::Accounts::ScanSolo::ReportsController < Api::V1::Accounts::ScanSolo::BaseController
  ANCHOR_FORMAT = /\A\d{4}-\d{2}-\d{2}\z/

  before_action :validate_period
  before_action :validate_anchor

  def index
    authorize(Current.account, :index?, policy_class: ::ScanSolo::ReportPolicy)

    now = Time.current
    period = ::ScanSolo::Reports::Period.resolve(period: params[:period], anchor: anchor)
    snapshot = closed_week_snapshot(period, now)
    return render json: snapshot.payload if snapshot

    render json: ::ScanSolo::Reports::ReportBuilder.call(account: Current.account, period: period, now: now, source: 'live')
  end

  private

  def closed_week_snapshot(period, now)
    return unless period.period == 'week' && period.closed?(now)

    ::ScanSolo::ReportSnapshot.find_by(account_id: Current.account.id, week_start: period.starts_at.to_date)
  end

  def anchor
    return Time.current.in_time_zone(::ScanSolo::Reports::Period::TIMEZONE).to_date if params[:anchor].blank?

    Date.strptime(params[:anchor], '%Y-%m-%d')
  end

  def validate_period
    return if ::ScanSolo::Reports::Period::PERIODS.include?(params[:period])

    render json: { error: 'invalid_period' }, status: :unprocessable_entity
  end

  def validate_anchor
    return if params[:anchor].blank?
    return if params[:anchor].to_s.match?(ANCHOR_FORMAT) && Date.valid_date?(*params[:anchor].split('-').map(&:to_i))

    render json: { error: 'invalid_anchor' }, status: :unprocessable_entity
  end
end
