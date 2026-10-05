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
| 14 | Mock proposal generation runs through Make-compatible contract | `spec/integration/scan_solo/full_test_mode_spec.rb` (item 14), `spec/services/scan_solo/proposal/generate_service_spec.rb`, `spec/services/scan_solo/proposal/mock_provider_spec.rb`, `spec/services/scan_solo/make/outbound_request_service_spec.rb`, `spec/requests/webhooks/scan_solo/make_spec.rb` |
| 15 | Proposal cannot report sent before successful send evidence | `spec/integration/scan_solo/full_test_mode_spec.rb` (item 15), `spec/services/scan_solo/proposal/send_service_spec.rb` |
| 16 | Successful proposal send moves stage and enrolls configured cadence | `spec/integration/scan_solo/full_test_mode_spec.rb` (item 16), `spec/services/scan_solo/proposal/send_service_spec.rb`, `spec/services/scan_solo/proposal/success_handler_spec.rb` |
| 17 | Duplicate jobs/webhooks/callbacks do not duplicate side effects | `spec/integration/scan_solo/full_test_mode_spec.rb` (item 17), `spec/jobs/scan_solo/ai_turn_job_spec.rb`, `spec/jobs/scan_solo/cadence_due_attempt_job_spec.rb`, `spec/requests/webhooks/scan_solo/make_spec.rb`, `spec/services/scan_solo/actions/executor_spec.rb` |
| 18 | Relevant operations are auditable | `spec/integration/scan_solo/full_test_mode_spec.rb` (item 18), `spec/services/scan_solo/audit_logger_spec.rb`, `spec/requests/api/v1/accounts/scan_solo/executions_spec.rb` |
| 19 | No production token/key/number is required for the test suite | `spec/integration/scan_solo/full_test_mode_spec.rb` (item 19), `spec/support/scansolo_webmock_enforcement.rb`, `spec/services/scan_solo/test_mode/mock_llm_provider_spec.rb`, `spec/services/scan_solo/proposal/mock_provider_spec.rb` |

## Reproducibility guarantee

Every spec file listed above:

- creates its own fixtures inline (accounts, contacts, conversations, agent configs) — no seeded/shared production data is required;
- runs under the global `WebMock.disable_net_connect!(allow_localhost: true)` gate (`spec/spec_helper.rb`), reinforced for the integration suite by `spec/support/scansolo_webmock_enforcement.rb`;
- never reads a production credential — every external boundary (LLM, embeddings, WhatsApp/Meta transport, Make) is exercised through its `ScanSolo::TestMode::*`/`ScanSolo::Proposal::MockProvider` seam or an explicit `webmock` stub.

## Operação centralizada (scansolo-operacao-centralizada)

Maps every RF/UI id of `.spec/features/scansolo-operacao-centralizada/SPEC.md` to the automated test(s) that cover it. The end-to-end proofs live in `spec/integration/scan_solo/operacao_centralizada_spec.rb` (scenarios a–f and e') and `spec/integration/scan_solo/legacy_compatibility_spec.rb` (RNF-10). RF-48 to RF-52 are operational requirements executed in Make (tasks T36–T39) and verified by execution records, not by the Rails suite.

| Id | Requirement | Automated test(s) |
|---|---|---|
| RF-01 | Structured lead origin that never changes the cadence | `spec/models/scan_solo/pipeline_opportunity_spec.rb`, `spec/services/scan_solo/pipeline/lead_source_classifier_spec.rb` |
| RF-02 | Bootstrap records the origin from the first message | `spec/services/scan_solo/pipeline/opportunity_bootstrap_service_spec.rb`, `spec/services/scan_solo/pipeline/lead_source_classifier_spec.rb` |
| RF-03 | Idempotent origin backfill | `spec/lib/tasks/scansolo_rake_spec.rb` |
| RF-04 | Contact found or created without duplicates | `spec/services/scan_solo/pipeline/manual_lead_service_spec.rb` |
| RF-05 | Invalid "Novo lead" input → 422 and 0 records | `spec/requests/api/v1/accounts/scan_solo/pipeline_opportunities_create_spec.rb` |
| RF-06 | Conversation + manual `novo_lead` opportunity in one transaction | `spec/services/scan_solo/pipeline/manual_lead_service_spec.rb` |
| RF-07 | Initial template through the native sender after commit | `spec/services/scan_solo/pipeline/manual_lead_outreach_spec.rb`, `spec/integration/scan_solo/operacao_centralizada_spec.rb` |
| RF-08 | Initial template failure keeps the lead and is visible | `spec/services/scan_solo/pipeline/manual_lead_outreach_spec.rb`, `spec/services/scan_solo/messaging/delivery_reconciler_spec.rb` |
| RF-09 | Contact with an open opportunity → 422 `opportunity_exists` | `spec/requests/api/v1/accounts/scan_solo/pipeline_opportunities_create_spec.rb` |
| RF-10 | Step 1 consumed, steps 2–4 at 24/48/96 h | `spec/services/scan_solo/pipeline/manual_lead_service_spec.rb` |
| RF-11 | Manual lead follows the natural flow on the first reply | `spec/integration/scan_solo/operacao_centralizada_spec.rb` |
| RF-12 | Completion with next action `proposta` → 1 native e-mail | `spec/services/scan_solo/quote/request_service_spec.rb`, `spec/services/scan_solo/lead_state/completion_service_spec.rb`, `spec/integration/scan_solo/operacao_centralizada_spec.rb` |
| RF-13 | Quote request e-mail content | `spec/services/scan_solo/quote/email_composer_spec.rb` |
| RF-14 | Misconfigured quote inbox fails visibly | `spec/services/scan_solo/quote/request_service_spec.rb`, `spec/services/scan_solo/quote/mailbox_spec.rb` |
| RF-15 | At most 1 quote request per completion | `spec/services/scan_solo/quote/request_service_spec.rb`, `spec/models/scan_solo/quote_request_spec.rb` |
| RF-16 | Quote inbox never reaches the AI | `spec/services/scan_solo/conversation_listener_spec.rb` |
| RF-17 | Valid block read deterministically | `spec/services/scan_solo/quote/response_block_parser_spec.rb`, `spec/services/scan_solo/quote/reply_processor_spec.rb` |
| RF-18 | Invalid block → correction request, 0 versions | `spec/services/scan_solo/quote/reply_processor_spec.rb`, `spec/integration/scan_solo/operacao_centralizada_spec.rb` |
| RF-19 | Reply without a request → pending link | `spec/services/scan_solo/quote/reply_processor_spec.rb`, `spec/requests/api/v1/accounts/scan_solo/quote_replies_spec.rb` |
| RF-20 | Manual link reprocesses the reply | `spec/requests/api/v1/accounts/scan_solo/quote_replies_spec.rb`, `spec/services/scan_solo/quote/pending_reply_resolution_spec.rb`, `spec/integration/scan_solo/operacao_centralizada_spec.rb` |
| RF-21 | 0 LLM calls on commercial fields | `spec/services/scan_solo/quote/reply_processor_spec.rb` |
| RF-22 | Correlation chain navigable from the opportunity | `spec/services/scan_solo/quote/reply_processor_spec.rb`, `spec/integration/scan_solo/operacao_centralizada_spec.rb` |
| RF-23 | Late reply → pending, only "Descartar" | `spec/services/scan_solo/quote/reply_processor_spec.rb`, `spec/requests/api/v1/accounts/scan_solo/quote_replies_spec.rb` |
| RF-24 | Validated reply → 1 Make generation with `commercial` | `spec/services/scan_solo/proposal/generate_service_spec.rb`, `spec/services/scan_solo/proposal/make_provider_spec.rb`, `spec/integration/scan_solo/operacao_centralizada_spec.rb` |
| RF-25 | Generation without a validated reply → 422; no `proposal_generate` offered | `spec/requests/api/v1/accounts/scan_solo/proposals_spec.rb`, `spec/services/scan_solo/ai_turn/input_guardrail_spec.rb` |
| RF-26 | "Generated" only by a valid callback; Rails proposal number; `valid_until` | `spec/requests/webhooks/scan_solo/make_spec.rb`, `spec/services/scan_solo/proposal/callback_handler_spec.rb`, `spec/models/scan_solo/proposal_version_spec.rb` |
| RF-27 | Generation failure → `failed` + existing retry | `spec/services/scan_solo/proposal/retry_policy_spec.rb`, `spec/services/scan_solo/proposal/callback_handler_spec.rb` |
| RF-28 | No additional approval | `spec/services/scan_solo/proposal/delivery_service_spec.rb`, `spec/integration/scan_solo/operacao_centralizada_spec.rb` |
| RF-29 | PDF in ActiveStorage, template with the PDF header, 0 `proposal.send` | `spec/services/scan_solo/proposal/delivery_service_spec.rb`, `spec/integration/scan_solo/operacao_centralizada_spec.rb` |
| RF-30 | `sent` only on WhatsApp acceptance → `proposta_enviada` + cadence | `spec/services/scan_solo/messaging/delivery_reconciler_spec.rb`, `spec/services/scan_solo/proposal/success_handler_spec.rb` |
| RF-31 | 1 follow-up after `sent` | `spec/services/scan_solo/proposal/follow_up_service_spec.rb`, `spec/integration/scan_solo/operacao_centralizada_spec.rb` |
| RF-32 | Delivery failure → `failed`, redelivery without Make | `spec/services/scan_solo/proposal/delivery_service_spec.rb`, `spec/services/scan_solo/proposal/retry_policy_spec.rb` |
| RF-33 | `generated` never moves the stage | `spec/services/scan_solo/proposal/delivery_service_spec.rb`, `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/specs/KanbanBoard.spec.js` |
| RF-34 | Post-proposal turns unchanged | `spec/integration/scan_solo/operacao_centralizada_spec.rb`, `spec/services/scan_solo/ai_turn/output_validator_spec.rb` |
| RF-35 | Negotiation signal → standard reply, `negociacao`, handoff | `spec/services/scan_solo/ai_turn/attempt_runner_spec.rb`, `spec/services/scan_solo/negotiation/request_service_spec.rb`, `spec/integration/scan_solo/operacao_centralizada_spec.rb` |
| RF-36 | AI never reaches `negociacao` by `stage_transition` | `spec/services/scan_solo/actions/stage_transition_action_spec.rb` |
| RF-37 | Negotiation e-mail with the 9 items | `spec/services/scan_solo/notifications/email_adapter_spec.rb`, `spec/services/scan_solo/notifications/negotiation_payload_spec.rb` |
| RF-38 | Native assignment to the commercial user | `spec/services/scan_solo/negotiation/request_service_spec.rb`, `spec/integration/scan_solo/operacao_centralizada_spec.rb` |
| RF-39 | Notification failure never undoes the negotiation | `spec/services/scan_solo/negotiation/request_service_spec.rb` |
| RF-40 | AI silent outside `ai_active` | `spec/services/scan_solo/ai_turn/attempt_runner_spec.rb`, `spec/integration/scan_solo/operacao_centralizada_spec.rb` |
| RF-41 | Replaceable notification channel | `spec/services/scan_solo/notifications/publisher_spec.rb` |
| RF-42 | Reply to a notification ignored | `spec/services/scan_solo/quote/reply_processor_spec.rb` |
| RF-43 | Reply cancels the pending attempt, ≤ 1 per cycle | `spec/services/scan_solo/cadence/reply_interruption_service_spec.rb`, `spec/services/scan_solo/conversation_listener_spec.rb` |
| RF-44 | Cadence definitions untouched (diff checked in T35) | `spec/models/scan_solo/cadence_definition_spec.rb` |
| RF-45 | Internal field classification untouched, display labels only | `spec/models/scan_solo/lead_state_spec.rb`, `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/specs/OpportunityDetail.spec.js` |
| RF-46 | Same 6 AI control states, no parallel mechanism | `spec/models/scan_solo/conversation_extension_spec.rb` |
| RF-47 | Deterministic amount in words sent to Make (Rails side) | `spec/services/scan_solo/quote/amount_in_words_spec.rb`, `spec/services/scan_solo/proposal/make_provider_spec.rb` |
| RF-48 | `artifact_url` downloadable PDF (operational, T38/T39) | operacional (Make) |
| RF-49 | Make failures → signed `failure` callback (operational, T38) | operacional (Make) |
| RF-50 | Make idempotency by `pv_` (operational, T38) | operacional (Make) |
| RF-51 | Legacy Make scenarios inactive with backup (operational, T36/T37) | operacional (Make) |
| RF-52 | Nothing activated before HG-03 (operational, T39) | operacional (Make) |
| RF-53 | 1 "orçamento em preparação" notice per request | `spec/services/scan_solo/quote/request_service_spec.rb`, `spec/integration/scan_solo/operacao_centralizada_spec.rb` |
| RF-54 | 3 fields in the existing published configuration | `spec/requests/api/v1/accounts/scan_solo/ai_agent_configs_spec.rb`, `app/javascript/dashboard/routes/dashboard/scansolo/agent/specs/AgentCenter.spec.js` |
| RF-55 | Approve/send/toggle disabled (Etapa 1), history preserved | `spec/integration/scan_solo/operacao_centralizada_spec.rb`, `spec/integration/scan_solo/legacy_compatibility_spec.rb`, `app/javascript/dashboard/routes/dashboard/scansolo/proposals/specs/Proposals.spec.js` |
| RF-56 | Manual, audited and idempotent quote request resend | `spec/requests/api/v1/accounts/scan_solo/quote_request_resend_spec.rb`, `spec/services/scan_solo/quote/resend_service_spec.rb`, `spec/integration/scan_solo/operacao_centralizada_spec.rb` |
| UI-01 | "Novo lead" button and form | `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/specs/NewLeadDialog.spec.js`, `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/specs/KanbanBoard.spec.js` |
| UI-02 | Kanban card fields | `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/specs/KanbanBoard.spec.js` |
| UI-03 | Card opens the opportunity detail | `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/specs/KanbanBoard.spec.js` |
| UI-04 | Lead screen with collected/to confirm/missing and statuses | `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/specs/OpportunityDetail.spec.js` |
| UI-05 | Pending replies on the Proposals screen | `app/javascript/dashboard/routes/dashboard/scansolo/proposals/specs/QuoteRepliesPending.spec.js` |
| UI-06 | No Approve/Send/toggle, readable history | `app/javascript/dashboard/routes/dashboard/scansolo/proposals/specs/Proposals.spec.js`, `app/javascript/dashboard/routes/dashboard/scansolo/agent/specs/AgentCenter.spec.js` |
| UI-07 | Quote request resend action for admins only | `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/specs/OpportunityDetail.spec.js` |
