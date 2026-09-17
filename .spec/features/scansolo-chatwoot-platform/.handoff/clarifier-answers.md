# Clarifier answers — scansolo-chatwoot-platform

## Q-01 / RF-12 — Kanban stale-indicator threshold
**Answer**: 48 hours of no customer interaction marks the opportunity as stale. Fixed constant, not per-account configurable for this phase.

## Q-02 / RF-54 — return-to-AI authorization role
**Answer**: The same role authorized to take over the conversation (assigned agent or administrator) may authorize return-to-AI — symmetric with the takeover policy. No new authorization concept.

## Q-03 / RF-65 — full vs. partial customer reply detection
**Answer**: Use qualification-field completeness as the detection rule — a "full" reply is one that leaves all required qualification fields satisfied per the current stage's requirements (reusing the RF-16 "all required fields satisfied" pattern); anything short of that is "partial." Deterministic, no NLP/intent classifier dependency.

## Q-04 / RNF-05 — rate-limiting scope
**Answer**: Scope is the Make inbound-callback endpoint only (developer selected this option, not the AI-turn or manual-enrollment alternatives). Implement via the existing `Rack::Attack` pattern (`config/initializers/rack_attack.rb`), since this is an unauthenticated external caller. Numeric threshold left to the planner/implementer to size against existing throttle ranges in that initializer (5–3000/min) — no specific number was mandated by the developer.

## Q-05 / RNF-06 — replay-protection retention window
**Answer**: Permanent DB-level uniqueness constraint on the correlation id — no TTL. No expiry, so a replayed callback is rejected indefinitely.
