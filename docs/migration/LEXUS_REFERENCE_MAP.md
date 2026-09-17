# Lexus CRM Reference Map for ScanSolo Chatwoot

## Purpose

This document identifies proven behavior in `lobernardo/lexus-crm` that should be **reimplemented or preserved conceptually** in the new ScanSolo Chatwoot platform.

Lexus is a reference source only. The final ScanSolo runtime must not depend on Lexus after cutover.

Do not copy Laravel/PHP classes mechanically into Rails. Preserve the behavior, invariants and safety properties using native Chatwoot/Rails architecture.

---

## 1. Agent runtime

### Lexus reference

`app/Services/AiAgentService.php`

Confirmed behavior worth preserving:

- per-agent configuration;
- provider/model abstraction;
- prompt assembled from persona + business rules + structured agent fields;
- canonical conversation history included in the turn;
- auxiliary durable memory recall/remember;
- knowledge/vector search exposed only when configured;
- tool registry and bounded tool exposure;
- token/cost/latency measurement;
- evidence captured per turn;
- test mode with a reduced capability set;
- provider failure does not become trusted business data.

Relevant configuration concepts to preserve:

- name;
- role;
- objective;
- persona;
- playbook;
- general instructions;
- tone;
- service rules;
- restricted information;
- transfer criteria;
- response limits;
- forbidden subjects;
- service hours;
- channel behavior.

### New platform target

Implement these concepts inside the custom Chatwoot AI Agent Center.

Native Chatwoot conversation/message records should replace Lexus canonical conversation persistence.

---

## 2. Canonical conversational turn

### Lexus reference

`app/Services/ConversationReplyService.php`

Important ordering/invariants:

```text
inbound already persisted
 -> trusted conversation/context lookup
 -> correlation validation
 -> reserve/dedupe processing attempt
 -> suppression/human-control/blocked check
 -> input guardrail
 -> resolve bounded capabilities/actions for the turn
 -> proposal confirmation resolution when relevant
 -> AI invocation with local history + knowledge + memory
 -> audit/evidence
 -> reject empty/ungrounded output
 -> persist accepted outbound once
 -> delivery delegated to channel
```

Properties to preserve:

- same inbound cannot produce duplicate automatic replies;
- idempotency is explicit;
- human/blocked state suppresses AI before model output is delivered;
- ungrounded transactional claims are suppressed;
- generation/tool evidence is auditable;
- repeated agent failure can cause human escalation;
- channel transport is separate from the reasoning turn.

### New platform target

Use native Chatwoot inbound/outbound messages and background jobs, but retain an explicit per-turn processing record/idempotency mechanism.

---

## 3. Human control / handoff

### Lexus reference

`app/Services/ConversationStateService.php`

Current state semantics:

```text
agent_active
handoff_requested
awaiting_human
human_active
paused
closed
```

Important rules:

- transitions are explicit and validated;
- human-active requires a human assignment/control context;
- takeover and return to agent are auditable/idempotent operations;
- paused conversations retain the controller semantics;
- closed conversations may reopen under explicit rules.

### New platform target

Map as much as possible onto native Chatwoot conversation status, assignment and AgentBot behavior.

Add a small custom AI-control state only if native Chatwoot status is insufficient to represent:

- AI owns conversation;
- handoff pending;
- human owns conversation;
- automation paused;
- authorized return to AI.

Do not create a second conversation model.

On handoff, add a private note with:

- reason;
- customer objective;
- summary;
- qualification fields;
- objections;
- pipeline stage;
- proposal status;
- pending actions;
- next recommended step.

---

## 4. Capabilities and action enforcement

### Lexus reference

The current agent architecture uses concepts equivalent to:

- `AgentToolRegistry`;
- `AgentCapabilityService`;
- `AgentCapabilityEnforcementService`;
- `AgentActionService`;
- policies Automatic / RequiresConfirmation / Disabled;
- per-turn capability resolution;
- schema-bound actions;
- explicit idempotency and audit.

`app/Workflow/Catalog/ActionCatalog.php` currently exposes registered behaviors including:

- `contact.locate`;
- `contact.create`;
- `contact.update`;
- `deal.locate_open`;
- `deal.create`;
- `deal.update`;
- `deal.move_stage`;
- `task.create`;
- `deal_note.create`;
- `information.record`;
- `message.send_template`;
- `email.send_template`;
- `delay.schedule`;
- `contact.reassign`;
- tag actions;
- collaborator notifications;
- `webhook.call`;
- `agent.invoke_action`;
- `conversation.transfer_human`.

### New platform target

Do not reproduce the full Lexus CRM tool catalog when Chatwoot owns the data natively.

Create only the actions ScanSolo actually needs, implemented through native Chatwoot services/models and custom commercial modules.

Minimum conceptual action set:

- read/update allowed contact qualification fields;
- request deterministic pipeline transition;
- request handoff;
- create private operational note;
- request proposal generation;
- request proposal approval/send;
- emit cadence/workflow signal;
- retrieve registered knowledge;
- send registered/approved material if later required.

No action may let the model choose arbitrary URLs, HTTP methods, SQL, scripts, secrets or direct provider credentials.

---

## 5. Knowledge / RAG

### Lexus reference

`AiAgentService` currently combines:

- canonical local conversation history;
- auxiliary memory;
- vector-store knowledge;
- live tools/context.

The current OpenAI path can expose file search through a configured provider vector store.

### New platform target

Preserve the separation:

```text
Chatwoot conversation history = primary continuity
RAG = company/service knowledge
memory = optional auxiliary durable facts
registered actions = live operational data/actions
```

The planner must choose a self-hosted-friendly vector design after inspecting Chatwoot and the target VPS stack. Do not assume an OpenAI-managed vector store is mandatory.

Required UI:

- documents;
- FAQs;
- service knowledge;
- source status;
- indexing/reindex;
- retrieval test;
- evidence/source display.

---

## 6. Pipeline

### Lexus behavior to preserve

ScanSolo target pipeline:

1. Novo Lead
2. Em Contato
3. Em Qualificação
4. Qualificado
5. Proposta Enviada
6. Negociação
7. Ganho
8. Perdido

Desired automatic semantics established in the current project:

- real lead interaction can move the opportunity to Em Contato;
- qualification activity moves to Em Qualificação;
- deterministic required-field completion moves to Qualificado;
- confirmed proposal send moves to Proposta Enviada;
- human takeover may suggest Negociação but must not invent/force a stage outside configured rules.

### New platform target

Implement first-class persisted pipeline state plus Kanban.

Labels/custom attributes may mirror state for filtering but are not the authoritative stage record.

Preserve stage history and next-follow-up visibility.

---

## 7. Cadence engine

### Lexus reference

`app/Services/CadenceEnrollmentService.php`

Important properties:

- enrollment is idempotent;
- same idempotency key with different input is a conflict;
- only one equivalent active enrollment should survive;
- cadence snapshot/version is preserved at enrollment;
- destination is snapshotted;
- timezone/schedule are stored;
- first step is reserved immediately;
- cancel operation cancels pending steps;
- templates/channel/destination are validated before enrollment.

`app/Workflow/Catalog/TriggerCatalog.php` includes signals such as:

- `deal.stage.entered`;
- `deal.stage.exited`;
- `deal.stage.time_elapsed`;
- `conversation.no_response`;
- `proposal.sent`;
- `conversation.message.received`;
- `schedule.due`.

### ScanSolo cadence decisions to preserve

#### Novo Lead

- 4 attempts: +2h / +24h / +48h / +96h.

#### Em Contato

- 5 attempts;
- initial configured interval: 24h.

#### Em Qualificação

- 7 attempts;
- initial configured interval: 24h.

#### Send window

- 09:00–20:00 America/Sao_Paulo;
- seven days/week.

#### Stop/recalculation

- customer reply;
- partial reply cancels immediate pending job and remaining work is reevaluated;
- human takeover;
- stage change;
- won/lost;
- opt-out;
- manual pause;
- replacement/cancellation.

### New platform target

Implement the cadence engine using Chatwoot/Rails persistence and Sidekiq/background-job architecture.

Templates must come from the connected native WhatsApp inbox/provider template catalog once production is connected.

---

## 8. Proposal automation

### Lexus references

Relevant existing behavior includes:

- tenant-specific action rather than a universal hardcoded agent feature;
- separate generate/approve/send concepts;
- callback validation;
- correlation and idempotency;
- approved/current proposal version protection;
- send requested/succeeded state;
- follow-up starts only after validated successful proposal delivery event.

`app/Providers/ScanSoloProposalSendCallbackHandler.php` demonstrates important protections:

- invocation must be completed/successful;
- tenant/action identity must match;
- proposal version must be approved/current for the correlation;
- send idempotency key is tied to the proposal version;
- final delivery job is dispatched only after the validated callback.

`app/Listeners/EnrollProposalSentCadence.php` demonstrates an important rule:

- generic `proposal.sent` is emitted only after successful validated delivery;
- workflow/cadence configuration decides timing/content;
- duplicate success events derive the same enrollment idempotency key.

### New platform target

Preserve these safety semantics inside the Chatwoot fork.

Make remains the preferred integration for the ScanSolo-specific proposal generation process.

The new platform must not depend on the current Lexus proposal tables after cutover.

---

## 9. Make integration

### Lexus behavior worth preserving

Registered external operations follow the pattern:

```text
agent/action request
 -> schema validation
 -> autonomy/authorization
 -> idempotency/correlation
 -> asynchronous integration request
 -> signed/authenticated external operation
 -> callback
 -> credential/correlation/replay/schema validation
 -> persist result
 -> bounded native command / final response
```

The model never chooses:

- URL;
- HTTP method;
- token;
- secret;
- tenant identifier;
- arbitrary callback command.

### New platform target

Build a lightweight registered integration layer sufficient for ScanSolo, not a copy of the entire Lexus integration product.

Initial integration: proposal generation through Make.

---

## 10. Audit, idempotency and evidence

### Lexus behavior worth preserving

- every external side effect has an idempotency identity;
- correlation IDs cross AI/integration/delivery boundaries;
- retries must not duplicate side effects;
- duplicate events return/reuse the prior result where safe;
- same idempotency key with materially different input is a conflict;
- agent turns record usage/evidence;
- human state changes are auditable;
- workflow/cadence executions expose failures/retry state.

### New platform target

Use native Chatwoot audit/event structures where sufficient and add isolated custom execution records only where required for AI, pipeline, cadence, proposal and integration observability.

---

## 11. Test mode

### Lexus behavior worth preserving

The current agent has a controlled test mode that does not expose normal unrestricted write capabilities by default.

### New platform target

Before connecting production providers, the application must support:

- fake Chatwoot conversation/customer;
- mock model;
- RAG retrieval test;
- mock actions;
- mock proposal/Make callback;
- fake provider templates;
- cadence time simulation/acceleration where practical;
- handoff simulation;
- no real WhatsApp/API side effects.

---

## 12. What must NOT be ported blindly

Do not port these Lexus-specific structures merely because they exist:

- Laravel tenant global scopes;
- Laravel-specific models/controllers/services;
- Lexus navigation/dashboard modules unrelated to ScanSolo;
- generic multi-tenant CRM modules that native Chatwoot already replaces;
- Evolution API support;
- direct Meta transport code if native Chatwoot already owns the WhatsApp channel;
- duplicated Contact/Conversation/Message entities;
- duplicated team/assignment UI;
- all generic Lexus workflow actions when a smaller ScanSolo-specific action set is sufficient.

The target is a clean Chatwoot-based ScanSolo product, not Lexus rewritten in Ruby.
