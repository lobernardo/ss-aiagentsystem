# Clarifier answers — developer decisions

- Q-01 (RF-23): A — first eligible inbound leaves opportunity in `novo_lead`; the next inbound moves to `em_contato`. Novo Lead cadence (+2h/+24h/+48h/+96h) covers leads silent after first AI reply. Remove the marker.
- Q-02 (RF-16, RF-31): B — opt-out detected by model `cadence_signal opt_out` action AND deterministic configurable keyword list (e.g. PARAR/SAIR/STOP) on inbound; admin can clear the flag, emitting an audit event. No auto-reset.
- Q-03 (RF-38, RF-48, D-05): A — generate: any agent; approve: admin only; send: admin or opportunity owner. Add policy rules + 403 request specs (RF-48/CT-04) and role-based buttons in UI-13.
- Q-04 (RF-18, D-09): A — only a manual non-private human reply triggers takeover; assignment never does. Fix the SPEC's Context wording: this is a deliberate deviation from D-09's recommended option (assignment excluded to avoid auto-assign pausing AI), not D-09 as written.

## Non-blocking notes to also apply (wording/AC fixes, no scope change)
- D-22: mark "AI answers 24/7, rules as instructions" as an interim default (DECISIONS_REQUIRED has no recommendation), not "recommended".
- D-19 / D-21: record explicitly as deliberate deviations from the docs' recommended option, with rationale; D-21 runbook note: pre-cutover setup relies on empty allowlist (RF-03/RF-26(3)) since flag off hides UI/API.
- RF-11: burst AC must state the model call is stubbed slow (no debounce) so "3 msgs in 2s → 1 reply" is deterministic.

## Round 2 (follow-up)
- Keyword match: whole-message match after normalization (trim, case-insensitive, strip accents, strip punctuation). "Parar!" matches; "não vou parar agora" does not (intent phrases left to the model). Add AC examples.
- Opt-out UI: yes, minimal, P1 (after P0): keyword list field in Agent Center + admin-only "remover opt-out" action in the contact panel (uses CT-11). Add UI requirement(s), i18n in en.json.
- Accepted clarifier assumptions: keywords on agent config (CT-01); CT-11 `DELETE /contacts/{contact_id}/opt_out` admin-only; D-05 rationale verified (OSS AccountUser roles are only agent/administrator); UI-13 retry admin-only.
