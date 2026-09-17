# ScanSolo AI Agent System

Custom ScanSolo conversational sales platform based on **Chatwoot Community Edition**.

## Product goal

Provide one operational system for ScanSolo at a future production domain under `scansolo.com.br`, with:

- official Meta WhatsApp inbox;
- AI sales/service agent;
- human handoff;
- contact context;
- commercial pipeline / Kanban;
- knowledge base and RAG;
- deterministic follow-up cadences using approved Meta templates;
- proposal generation through registered Make integrations;
- execution/audit visibility;
- self-hosted deployment on Linux VPS + Docker Compose.

## Architecture principle

Chatwoot Community is the product foundation and conversational center. ScanSolo-specific capabilities are implemented as isolated, maintainable extensions of the Community codebase. The previous Lexus CRM implementation is a **reference source for proven behavior and contracts**, not a runtime dependency after cutover.

```text
Website / WhatsApp
        |
        v
Meta WhatsApp Cloud API
        |
        v
ScanSolo Chatwoot
  |-- Conversations / Contacts / Human Service
  |-- Meta Templates
  |-- Pipeline / Kanban              [custom]
  |-- AI Agent Center                [custom]
  |-- Knowledge / RAG                [custom]
  |-- Follow-up Cadence Engine       [custom]
  |-- Proposal Status / Actions      [custom]
  |-- Audit / Execution Visibility   [custom]
        |
        +--> Make --> proposal / tenant-specific integrations
```

## Start here

- Architecture decision: [`docs/architecture/ADR-001-chatwoot-scansolo-platform.md`](docs/architecture/ADR-001-chatwoot-scansolo-platform.md)
- End-to-end flow: [`docs/architecture/END_TO_END_FLOW.md`](docs/architecture/END_TO_END_FLOW.md)
- bc-harness input: [`.spec/inputs/scansolo-chatwoot-platform.md`](.spec/inputs/scansolo-chatwoot-platform.md)
- Lexus behavior reference: [`docs/migration/LEXUS_REFERENCE_MAP.md`](docs/migration/LEXUS_REFERENCE_MAP.md)
- Runtime data inventory: [`docs/migration/RUNTIME_DATA_INVENTORY.md`](docs/migration/RUNTIME_DATA_INVENTORY.md)
- Chatwoot upstream findings: [`docs/upstream/CHATWOOT_CAPABILITY_NOTES.md`](docs/upstream/CHATWOOT_CAPABILITY_NOTES.md)
- Pre-harness runbook: [`docs/runbooks/PRE_HARNESS.md`](docs/runbooks/PRE_HARNESS.md)
- Final production cutover: [`docs/runbooks/PRODUCTION_CUTOVER.md`](docs/runbooks/PRODUCTION_CUTOVER.md)
- Upstream bootstrap script: [`scripts/bootstrap-chatwoot-upstream.sh`](scripts/bootstrap-chatwoot-upstream.sh)

## Licensing boundary

The upstream root license states that Chatwoot code outside restricted areas such as `enterprise/` is available under MIT Expat, while `enterprise/` has a separate proprietary license.

Custom ScanSolo implementation must be based on Community/MIT behavior or independently implemented requirements. Do not copy proprietary implementation from upstream `enterprise/` unless a valid Enterprise license is intentionally adopted later.

## Production activation is intentionally deferred

Do not connect the following until the complete system has passed isolated tests and a human cutover gate:

- real ScanSolo WhatsApp number;
- Meta production webhook and production access token;
- production OpenAI key;
- production Make webhooks/callbacks;
- real proposal credentials/API;
- final DNS and TLS cutover;
- real customer messaging;
- production migration/cutover from Lexus.

## Prepare the Chatwoot base

Clone this repository locally and run the safe bootstrap script:

```bash
cd /home/leonardool/projetos
git clone https://github.com/lobernardo/ss-aiagentsystem.git
cd ss-aiagentsystem
bash scripts/bootstrap-chatwoot-upstream.sh
```

After inspection, push the generated bootstrap branch:

```bash
git push -u origin bootstrap/chatwoot-base
```

The script does not replace `main` and does not connect any production provider.

## Planning flow

From the imported Chatwoot branch:

```text
/bc-harness:ai-context
```

Then:

```text
/bc-harness:plan ".spec/inputs/scansolo-chatwoot-platform.md"
```

Review `SPEC.md`, `PLAN.md` and `PHASES.md` before any implementation executor is allowed to run.
