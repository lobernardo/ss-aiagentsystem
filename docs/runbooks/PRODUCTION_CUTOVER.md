# Production Cutover Runbook — ScanSolo

## Status

Design only. Do not execute until the custom Chatwoot platform has passed implementation, staging, regression and human approval gates.

## Goal

Move ScanSolo from the current Lexus CRM runtime to the new ScanSolo Chatwoot platform without double responses, lost conversations, broken proposal automation or duplicated follow-ups.

## Preconditions

All must be true before cutover:

- staging build matches intended production release;
- all automated tests pass;
- AI test-mode scenarios pass;
- pipeline/Kanban scenarios pass;
- human takeover/return scenarios pass;
- cadence timing and stop-condition scenarios pass;
- Meta template mapping is validated in a non-customer test context where possible;
- proposal generate/approve/send mock and staging integrations pass;
- retry/idempotency tests pass;
- backup/restore test is documented;
- production VPS is hardened and monitored;
- database backup exists;
- rollback procedure is rehearsed/documented;
- operator explicitly approves the cutover window.

## Production values intentionally configured at the end

- final ScanSolo subdomain under `scansolo.com.br`;
- DNS records;
- TLS certificate;
- production Meta app/WhatsApp credentials;
- real ScanSolo WhatsApp number;
- production OpenAI key/model configuration;
- production Make webhook/callback credentials;
- production proposal API/service credentials;
- outbound e-mail credentials if required;
- object-storage production credentials;
- backup credentials/targets;
- monitoring/alert destinations.

Never place production secrets in Git.

## Data migration principle

Migrate only the ScanSolo state required for operational continuity.

Potential minimum set, subject to final mapping after implementation:

- contacts needed for active operations;
- phone/e-mail identity;
- active pipeline stage;
- qualification fields required by the agent;
- open proposal state/reference/version required for continuity;
- ownership/responsible person where required;
- current agent prompt/playbook/configuration;
- knowledge documents/sources;
- template mapping;
- active cadence handling decision.

Do not blindly import all Lexus tables/history.

For pending cadences, explicitly choose one cutover policy per enrollment:

- migrate current state safely; or
- cancel in Lexus and re-enroll deterministically in the new platform; or
- intentionally close with no further automation.

No enrollment may remain active in both systems.

## Single-owner rule

At any moment the real ScanSolo WhatsApp number must have only one active automatic-response owner.

Never allow both:

```text
Meta -> Lexus automatic agent
```

and

```text
Meta -> ScanSolo Chatwoot automatic agent
```

for the same live inbound flow.

Similarly, automated follow-up must have one owner only.

## Suggested cutover sequence

1. Freeze production configuration changes for ScanSolo in Lexus.
2. Export/record the approved migration snapshot.
3. Pause new Lexus ScanSolo cadence enrollments.
4. Reconcile existing pending cadence jobs and choose migrate/cancel/re-enroll disposition.
5. Backup Lexus ScanSolo operational state needed for rollback.
6. Backup the new Chatwoot production database/configuration.
7. Configure production OpenAI/Make/proposal credentials in the new platform.
8. Configure the real Meta/WhatsApp inbox in the new platform without enabling duplicate traffic prematurely.
9. Load/migrate approved ScanSolo operational state.
10. Validate contacts, pipeline, agent config, knowledge and proposal references.
11. Pause Lexus automatic agent and automated outbound for ScanSolo.
12. Switch the Meta webhook/number ownership to the new Chatwoot flow.
13. Send/receive a controlled operator-approved end-to-end WhatsApp test.
14. Verify inbound persistence.
15. Verify one AI reply only.
16. Verify human takeover.
17. Verify a controlled template send.
18. Verify delivery/failure evidence.
19. Verify a controlled proposal integration scenario if safe for the cutover window.
20. Observe logs/queues/errors before declaring activation complete.
21. Keep Lexus ScanSolo data available read-only for the rollback/verification period.

## Abort conditions

Abort/rollback if any of the following occurs:

- duplicate automatic responses;
- tenant/account identity ambiguity;
- inbound messages not persisted;
- agent sends without human-control enforcement;
- unexpected real sends from test/mock workflows;
- cadence duplicates;
- proposal send falsely reported as success;
- Meta delivery/webhook instability not understood;
- queue backlog beyond agreed operational threshold;
- database migration/data integrity issue;
- secrets/log leakage;
- critical human-service UI failure.

## Rollback principle

Rollback must restore a **single owner** for WhatsApp and automation.

Conceptual rollback:

1. stop new platform automatic jobs/outbound;
2. switch real Meta flow back to the previously validated Lexus path if still operationally supported;
3. ensure new-system pending cadence jobs cannot send;
4. re-enable only the explicitly required Lexus ScanSolo automation;
5. reconcile any conversations/messages that occurred during the attempted cutover;
6. document incident/correlation IDs before retrying migration.

Exact commands/routes depend on the final implemented systems and must be added to this runbook before production activation.

## Decommission of Lexus dependency

Only after an agreed verification period and explicit approval:

- remove ScanSolo real-provider credentials from the Lexus runtime where appropriate;
- disable ScanSolo automatic agent/outbound integrations in Lexus;
- preserve required audit/history backups;
- document the final cutover timestamp;
- confirm the new Chatwoot platform is the sole ScanSolo conversational/commercial runtime.

Do not delete production history merely because the runtime moved.
