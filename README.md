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

## Licensing boundary

The base must use Chatwoot Community/MIT-licensed code. Do not copy proprietary implementation from the upstream `enterprise/` directory into this repository unless a valid Enterprise license is intentionally adopted later.

## Production activation is intentionally deferred

Do not connect the following until the complete system has passed isolated tests and a human cutover gate:

- real ScanSolo WhatsApp number;
- Meta production webhook and production access token;
- production OpenAI key;
- production Make webhooks/callbacks;
- real proposal credentials/API;
- final DNS and TLS cutover;
- real customer messaging.

## Planning flow

This repository is prepared for the Beer and Code Harness workflow:

```text
Chatwoot upstream imported
    -> /bc-harness:ai-context
    -> .spec/inputs/scansolo-chatwoot-platform.md
    -> /bc-harness:plan ".spec/inputs/scansolo-chatwoot-platform.md"
    -> review SPEC.md / PLAN.md / PHASES.md
    -> feature-branch execution only
```

See `docs/` and `.spec/inputs/` before implementation.
