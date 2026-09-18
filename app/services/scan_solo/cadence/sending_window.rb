# RF-58: cadence messages only ever send between 09:00-20:00
# America/Sao_Paulo, any day of the week. Uses Rails' own
# ActiveSupport::TimeZone conversions (no hand-rolled offset math, per the
# PLAN's risk mitigation for DST/edge cases around this zone).
class ScanSolo::Cadence::SendingWindow
  ZONE = 'America/Sao_Paulo'
  START_HOUR = 9
  END_HOUR = 20

  def self.in_window?(time = Time.current)
    hour = time.in_time_zone(ZONE).hour
    hour >= START_HOUR && hour < END_HOUR
  end

  # The next in-window moment: today at START_HOUR if it's still earlier
  # than that today, otherwise tomorrow at START_HOUR.
  def self.next_in_window(time = Time.current)
    local = time.in_time_zone(ZONE)
    return local if in_window?(local)

    target_date = local.hour < START_HOUR ? local.to_date : local.to_date + 1.day
    ActiveSupport::TimeZone[ZONE].local(target_date.year, target_date.month, target_date.day, START_HOUR, 0, 0)
  end
end
