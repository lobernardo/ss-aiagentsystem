# frozen_string_literal: true

# RF-12: fixed, non-account-configurable staleness threshold for pipeline
# opportunities.
module ScanSolo
  PIPELINE_STALE_THRESHOLD = 48.hours
end
