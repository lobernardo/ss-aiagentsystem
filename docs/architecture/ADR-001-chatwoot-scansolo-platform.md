# ADR-001 — ScanSolo Platform on Chatwoot Community

## Status

Approved direction for planning. Production activation remains pending human approval.

## Context

ScanSolo currently depends on the Lexus CRM for the AI agent, WhatsApp transport, pipeline, proposal automation, follow-up workflows, integrations, audit, and human handoff.

The new product direction is to provide ScanSolo with a single operational system based on a customized self-hosted Chatwoot Community installation.

This ADR is intentionally **ScanSolo-specific**. It supersedes the previous Lexus-core architecture only for the future ScanSolo runtime after cutover. It does not change the architecture of Lexus CRM for other tenants.

## Decision

Use Chatwoot Community Edition as the application foundation and conversational center for ScanSolo.

The future ScanSolo solution will not require Lexus CRM as a runtime dependency after the controlled cutover.

The Chatwoot fork will reuse native Community capabilities wherever they already solve the problem and will add isolated ScanSolo modules for the missing commercial/AI behavior.

## Target topology

```text
ScanSolo website
       |
       v
WhatsApp official Meta
       |
       v
ScanSolo Chatwoot
  |-- native conversations
  |-- native contacts
  |-- native agents / teams / human service
  |-- native WhatsApp templates / transport
  |-- Pipeline / Kanban                [custom]
  |-- AI Agent Center                  [custom]
  |-- Knowledge / RAG                  [custom]
  |-- Follow-up cadence engine         [custom]
  |-- Proposal lifecycle               [custom]
  |-- Execution / audit visibility     [custom]
       |
       +--> Make --> proposal and external tenant-specific operations
```

## Hosting

Production target: **Linux VPS + Docker Compose**.

Expected runtime dependencies:

- Chatwoot web process;
- Sidekiq worker(s);
- PostgreSQL;
- Redis;
- S3-compatible object storage;
- reverse proxy and TLS;
- backup and recovery process;
- monitoring and log retention.

## Licensing boundary

The upstream root license states that code outside the `enterprise/` directory is MIT-licensed. Code under upstream `enterprise/` uses the Chatwoot Enterprise License.

Therefore:

- Community/MIT code may be used and modified subject to its license notices;
- the project must not copy proprietary `/enterprise` implementation into this Community fork;
- if a future Enterprise feature is desired, it must be independently implemented from requirements or intentionally licensed, not copied.

## Native Chatwoot responsibilities

Prefer native Community behavior for:

- Meta WhatsApp inbox and transport;
- conversations and messages;
- contacts;
- agents and teams;
- assignment;
- internal notes;
- attachments;
- conversation statuses;
- custom attributes;
- labels;
- REST API;
- webhooks;
- WhatsApp templates;
- basic automations.

## Custom ScanSolo responsibilities

Add only the missing capabilities:

1. commercial pipeline and Kanban;
2. AI Agent Center;
3. knowledge/RAG management;
4. safe conversational agent runtime;
5. deterministic follow-up cadence engine;
6. proposal lifecycle and Make integration;
7. AI/human control synchronization;
8. execution, evidence and audit views;
9. ScanSolo branding.

## Lexus reuse policy

Lexus CRM is a **reference implementation**, not a dependency.

Reuse its proven product behavior and contracts where appropriate, including:

- per-turn orchestration order;
- agent configuration concepts;
- canonical history before AI;
- RAG + auxiliary memory;
- input guardrails;
- output grounding;
- capability/action enforcement;
- idempotency and correlation;
- human handoff state semantics;
- deterministic cadence enrollment and stop conditions;
- proposal generate/approve/send separation;
- Make request/callback validation;
- audit and token/cost telemetry;
- isolated test mode.

Do not mechanically port Laravel/PHP classes into Rails. Map behavior to native Chatwoot/Rails abstractions.

## Follow-up ownership

The new Chatwoot-based system owns the complete cadence runtime.

Templates remain official Meta/WhatsApp templates exposed through Chatwoot. The custom cadence engine owns scheduling, retries, stop conditions, stage-specific policies, pause/resume/cancel and idempotency.

Initial ScanSolo rules to preserve:

- Novo Lead: 4 attempts at +2h, +24h, +48h and +96h;
- Em Contato: 5 attempts, initially 24h apart;
- Em Qualificação: 7 attempts, initially 24h apart;
- sending window: 09:00–20:00 America/Sao_Paulo, seven days/week;
- a partial customer reply cancels the immediate pending send and causes remaining work to be recalculated;
- customer reply, human takeover, stage change, won/lost, opt-out, pause or replacement must stop/recalculate applicable pending work.

## Pipeline

Initial ScanSolo pipeline:

1. Novo Lead
2. Em Contato
3. Em Qualificação
4. Qualificado
5. Proposta Enviada
6. Negociação
7. Ganho
8. Perdido

Pipeline state must be persisted authoritatively. Labels may mirror state but must not be the sole source of truth.

## Proposal integration

Proposal automation is ScanSolo-specific and uses registered Make integration contracts.

Conceptual lifecycle:

```text
qualification
 -> deterministic field validation
 -> proposal.generate
 -> Make/API
 -> validated result
 -> proposal.approve when required
 -> proposal.send
 -> confirmed send
 -> pipeline stage update
 -> post-proposal cadence
```

The model must never invent authoritative price, discount, total or successful delivery.

## Production gates

Implementation and tests must remain disconnected from production until explicit human approval.

Deferred until final cutover:

- real ScanSolo WhatsApp number;
- Meta production webhook/token;
- production OpenAI key;
- production Make endpoints;
- real proposal credentials;
- final `scansolo.com.br` subdomain;
- production DNS/TLS change;
- real customer messages;
- data migration/cutover from Lexus.

## Upstream strategy

Keep the fork close to Chatwoot upstream:

- additive migrations;
- isolated namespaces/modules;
- minimal modifications to upstream core;
- extension services instead of forks of existing flows;
- record every high-conflict customization;
- retain an `upstream` Git remote pointing to `chatwoot/chatwoot`;
- periodically evaluate upstream changes before merging them.
