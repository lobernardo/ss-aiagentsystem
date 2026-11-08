# RF-07/RF-09/RNF-07: resolves the report period (`week` or `month`) that
# contains `anchor`, in America/Sao_Paulo regardless of the server zone. Weeks
# start on Monday. The interval is half-open: `ends_at` is the start of the next
# period. `previous` is the immediately preceding period of the same type.
# Input validation lives in the controller.
class ScanSolo::Reports::Period
  TIMEZONE = 'America/Sao_Paulo'.freeze
  PERIODS = %w[week month].freeze

  attr_reader :period, :anchor, :starts_at, :ends_at

  def self.resolve(period:, anchor:)
    new(period: period, anchor: anchor.to_date)
  end

  def initialize(period:, anchor:)
    @period = period
    @anchor = anchor
    day = ActiveSupport::TimeZone[TIMEZONE].local(anchor.year, anchor.month, anchor.day)
    @starts_at = period == 'week' ? day.beginning_of_week(:monday) : day.beginning_of_month
    @ends_at = period == 'week' ? starts_at + 1.week : starts_at + 1.month
  end

  def previous
    self.class.resolve(period: period, anchor: starts_at.to_date - 1.day)
  end

  def range
    starts_at...ends_at
  end

  def closed?(now)
    ends_at <= now
  end
end
