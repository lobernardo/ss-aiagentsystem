# frozen_string_literal: true

# RF-12: fixed, non-account-configurable staleness threshold for pipeline
# opportunities.
#
# RF-11: an AI turn invokes the model with a bounded timeout and a single
# provider retry, and the per-conversation turn lock outlives that worst case
# so two turns of one conversation never overlap.
#
# RF-08/RNF-02: a turn still `pending` after AI_TURN_STALE_THRESHOLD is failed
# by ScanSolo::StaleTurnSweeperJob (operational default, adjustable here).
module ScanSolo
  PIPELINE_STALE_THRESHOLD = 48.hours

  AI_TURN_MODEL_TIMEOUT = 45.seconds
  AI_TURN_MODEL_MAX_RETRIES = 1
  AI_TURN_LOCK_TTL = 3.minutes
  AI_TURN_STALE_THRESHOLD = 10.minutes
end
