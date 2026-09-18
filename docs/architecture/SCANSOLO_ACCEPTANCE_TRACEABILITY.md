# ScanSolo Acceptance-Outcome Traceability Matrix

## Status

RF-92 deliverable. Maps every description §20 "Acceptance outcome before cutover" item (1-19) to the automated test(s) that reproduce it, so each item is independently verifiable without any production token, key, or phone number (RNF-03).

Item 20 ("Docker-based staging deployment and rollback instructions are documented") is a documentation-only deliverable, out of RF-92's scope (items 1-19), and is covered separately by Phase 15 (`docs/architecture/SCANSOLO_DEPLOYMENT.md`).

## How to reproduce

```bash
bundle exec rspec spec/integration/scan_solo/
```

runs to completion with no production credential present (`spec/support/scansolo_webmock_enforcement.rb` disables real HTTP via `WebMock.disable_net_connect!`, configured globally in `spec/spec_helper.rb`) and zero outbound requests to a real external endpoint. Every spec file referenced below can also be run individually via `bundle exec rspec <path>`.

## Matrix

| # | §20 acceptance outcome | Automated test(s) |
|---|---|---|
| 1 | Fake inbound message persists in native Chatwoot flow | `spec/integration/scan_solo/full_test_mode_spec.rb` (item 1), `spec/jobs/scan_solo/ai_turn_job_spec.rb` |
| 2 | AI processes one turn exactly once | `spec/integration/scan_solo/full_test_mode_spec.rb` (item 2), `spec/jobs/scan_solo/ai_turn_job_spec.rb`, `spec/db/scansolo_migrations_spec.rb` (unique index on `message_id`) |
| 3 | Agent uses canonical conversation history | `spec/integration/scan_solo/full_test_mode_spec.rb` (item 3), `spec/services/scan_solo/ai_turn/context_assembler_spec.rb` |
| 4 | RAG retrieval returns evidence | `spec/integration/scan_solo/full_test_mode_spec.rb` (item 4), `spec/services/scan_solo/knowledge/retrieval_service_spec.rb`, `spec/services/scan_solo/knowledge/ingestion_service_spec.rb` |
| 5 | Guardrails/action permissions are enforced | `spec/integration/scan_solo/full_test_mode_spec.rb` (item 5), `spec/services/scan_solo/actions/executor_spec.rb`, `spec/services/scan_solo/ai_turn/input_guardrail_spec.rb`, `spec/services/scan_solo/ai_turn/output_validator_spec.rb` |
| 6 | Pipeline state changes correctly and Kanban reflects it | `spec/integration/scan_solo/full_test_mode_spec.rb` (item 6), `spec/services/scan_solo/pipeline/stage_transition_service_spec.rb`, `spec/requests/api/v1/accounts/scan_solo/pipeline_opportunities_spec.rb` |
| 7 | AI handoff creates a private summary and suppresses further AI | `spec/integration/scan_solo/full_test_mode_spec.rb` (item 7), `spec/services/scan_solo/handoff/handoff_service_spec.rb` |
| 8 | Authorized return to AI works | `spec/integration/scan_solo/full_test_mode_spec.rb` (item 8), `spec/requests/api/v1/accounts/scan_solo/conversations/handoff_controller_spec.rb` |
| 9 | Novo Lead cadence schedules +2h/+24h/+48h/+96h correctly | `spec/integration/scan_solo/full_test_mode_spec.rb` (item 9), `spec/models/scan_solo/cadence_definition_spec.rb`, `spec/services/scan_solo/cadence/enrollment_service_spec.rb` |
| 10 | Customer response cancels/recalculates applicable pending cadence work | `spec/integration/scan_solo/full_test_mode_spec.rb` (item 10), `spec/services/scan_solo/cadence/reply_completeness_detector_spec.rb` |
| 11 | Human takeover pauses/stops applicable cadence work | `spec/integration/scan_solo/full_test_mode_spec.rb` (item 11), `spec/services/scan_solo/cadence/stop_recalculate_policy_spec.rb` |
| 12 | Stage change recalculates/replaces cadence according to policy | `spec/integration/scan_solo/full_test_mode_spec.rb` (item 12), `spec/services/scan_solo/cadence/stop_recalculate_policy_spec.rb` |
| 13 | Fake Meta template send runs through native Chatwoot messaging path | `spec/integration/scan_solo/full_test_mode_spec.rb` (item 13), `spec/services/scan_solo/messaging/native_template_sender_spec.rb` |
| 14 | Mock proposal generation runs through Make-compatible contract | `spec/integration/scan_solo/full_test_mode_spec.rb` (item 14), `spec/services/scan_solo/proposal/generate_service_spec.rb`, `spec/services/scan_solo/proposal/mock_provider_spec.rb`, `spec/services/scan_solo/make/outbound_request_service_spec.rb`, `spec/requests/webhooks/scan_solo/make_controller_spec.rb` |
| 15 | Proposal cannot report sent before successful send evidence | `spec/integration/scan_solo/full_test_mode_spec.rb` (item 15), `spec/services/scan_solo/proposal/send_service_spec.rb` |
| 16 | Successful proposal send moves stage and enrolls configured cadence | `spec/integration/scan_solo/full_test_mode_spec.rb` (item 16), `spec/services/scan_solo/proposal/send_service_spec.rb`, `spec/services/scan_solo/proposal/success_handler_spec.rb` |
| 17 | Duplicate jobs/webhooks/callbacks do not duplicate side effects | `spec/integration/scan_solo/full_test_mode_spec.rb` (item 17), `spec/jobs/scan_solo/ai_turn_job_spec.rb`, `spec/jobs/scan_solo/cadence_due_attempt_job_spec.rb`, `spec/requests/webhooks/scan_solo/make_controller_spec.rb`, `spec/services/scan_solo/actions/executor_spec.rb` |
| 18 | Relevant operations are auditable | `spec/integration/scan_solo/full_test_mode_spec.rb` (item 18), `spec/services/scan_solo/audit_logger_spec.rb`, `spec/requests/api/v1/accounts/scan_solo/executions_spec.rb` |
| 19 | No production token/key/number is required for the test suite | `spec/integration/scan_solo/full_test_mode_spec.rb` (item 19), `spec/support/scansolo_webmock_enforcement.rb`, `spec/services/scan_solo/test_mode/mock_llm_provider_spec.rb`, `spec/services/scan_solo/proposal/mock_provider_spec.rb` |

## Reproducibility guarantee

Every spec file listed above:

- creates its own fixtures inline (accounts, contacts, conversations, agent configs) — no seeded/shared production data is required;
- runs under the global `WebMock.disable_net_connect!(allow_localhost: true)` gate (`spec/spec_helper.rb`), reinforced for the integration suite by `spec/support/scansolo_webmock_enforcement.rb`;
- never reads a production credential — every external boundary (LLM, embeddings, WhatsApp/Meta transport, Make) is exercised through its `ScanSolo::TestMode::*`/`ScanSolo::Proposal::MockProvider` seam or an explicit `webmock` stub.
