# ScanSolo Chatwoot Platform — bc-harness Requirements Input

## Purpose

Create a customized self-hosted Chatwoot Community platform for ScanSolo, replacing the current Lexus CRM operational runtime for this tenant only after a controlled final cutover.

The final product must provide one central operational interface for conversations, human service, contact context, AI-assisted lead qualification, sales pipeline tracking, proposal automation, deterministic follow-up cadences, knowledge/RAG and execution visibility.

Production integrations remain disconnected until all features pass isolated testing.

## Planning authority

Before generating SPEC/PLAN/PHASES, inspect the real imported Chatwoot Community codebase and reconcile these requirements with its current architecture.

Do not treat conceptual class/module names in this document as mandatory implementation names.

The planner must:

1. inspect current Chatwoot Community models, services, jobs, APIs, webhooks, WhatsApp channel, AgentBot, automation engine, frontend routing/state and installation configuration;
2. identify Community vs `enterprise/` boundaries;
3. reuse native Community capabilities rather than creating parallel implementations;
4. inspect the Lexus reference map in `docs/migration/LEXUS_REFERENCE_MAP.md` for behavior worth preserving;
5. distinguish AS IS / TO BE / GAP / DECISION PENDING;
6. use additive/backward-compatible schema changes where practical;
7. define binary acceptance criteria and explicit test paths for every implementation task;
8. preserve upstream maintainability;
9. keep production deploy, real provider activation and real customer messaging outside autonomous implementation.

## 1. Product surface

The ScanSolo team must operate from one application.

Future production domain will be a subdomain of `scansolo.com.br`. Exact hostname is a final configuration decision; do not hardcode it in application logic.

Required primary modules:

1. **Conversas**
2. **Contatos**
3. **Pipeline**
4. **Agente de IA**
5. **Conhecimento**
6. **Follow-ups**
7. **Propostas**
8. **Equipe**
9. **Templates**
10. **Automação e integrações**
11. **Execuções e auditoria**

All user-facing interface copy must be Brazilian Portuguese (`pt-BR`). Source code, tests and technical documentation must be English.

## 2. Native Chatwoot behavior to reuse

Reuse current Community behavior wherever it already provides the required capability, including as applicable:

- WhatsApp/Meta inbox transport;
- conversations and messages;
- contacts;
- agents, teams and assignments;
- internal notes;
- attachments;
- conversation status;
- custom attributes;
- labels;
- REST APIs;
- authenticated webhooks;
- WhatsApp templates;
- human service;
- basic automations;
- Sidekiq background jobs;
- existing account/user authorization boundaries.

Do not create a parallel conversation, contact or messaging subsystem.

## 3. Branding

Prepare the Community fork so final ScanSolo branding can be applied without changing domain logic.

Support:

- installation name;
- ScanSolo logo;
- dark-mode logo where applicable;
- thumbnail/favicon;
- brand name/URL;
- login branding;
- page/application title;
- e-mail branding where Community code permits;
- configurable visual tokens where practical.

Actual logo files and final hostname are deferred until the finalization phase.

Do not copy proprietary Enterprise implementation.

## 4. Sales pipeline / Kanban

Create a first-class commercial pipeline with authoritative persisted stage state.

Initial stages:

1. Novo Lead
2. Em Contato
3. Em Qualificação
4. Qualificado
5. Proposta Enviada
6. Negociação
7. Ganho
8. Perdido

Required behavior:

- Kanban view;
- drag-and-drop with server-side validation;
- stage history;
- owner/responsible user;
- related Chatwoot contact and conversation;
- last customer interaction;
- next scheduled follow-up;
- inactivity/stale indicator;
- filters;
- authorized manual transitions;
- deterministic automatic transitions;
- audit history;
- won/lost terminal behavior;
- no source-of-truth dependency on labels alone.

Expected automatic behavior includes at minimum:

- customer begins real conversation -> Em Contato when applicable;
- qualification begins -> Em Qualificação;
- all configured qualification requirements are satisfied -> Qualificado;
- successful proposal send -> Proposta Enviada;
- human commercial negotiation may move to Negociação according to explicit rule/authorization.

The model must not arbitrarily choose a stage without registered deterministic criteria or an authorized action.

## 5. AI Agent Center

Add a central agent configuration module inside the ScanSolo application.

Preserve proven Lexus concepts but implement them natively in Rails/Chatwoot architecture.

Required configuration:

- agent name;
- enabled/disabled state;
- model provider abstraction, initially OpenAI-compatible;
- model selection;
- role;
- objective;
- persona/identity;
- tone;
- general instructions;
- service rules;
- qualification playbook;
- required qualification fields;
- restricted information;
- forbidden subjects;
- transfer criteria;
- response limits;
- service hours/channel behavior where applicable;
- draft/published configuration or equivalent safe versioning;
- test mode.

Required telemetry:

- invocation status;
- model/provider;
- input/output token counts where available;
- cost estimate where configured;
- latency;
- guardrail outcome;
- knowledge retrieval evidence;
- action/tool evidence;
- failure reason;
- correlation identifiers.

No production OpenAI key during implementation.

## 6. Knowledge / RAG

Provide a first-class knowledge center.

Support:

- document upload;
- FAQ entries;
- service/company knowledge;
- source metadata;
- chunking/indexing;
- embeddings/vector retrieval;
- source/evidence capture;
- enable/disable source;
- reindex/retry;
- retrieval test/simulator;
- deletion/revocation;
- safe failure when vector provider is unavailable.

Canonical Chatwoot conversation history is the primary continuity source. RAG and durable semantic memory are auxiliary context layers.

The planner must evaluate the most maintainable vector-store design for the self-hosted stack rather than assuming the Lexus/OpenAI-managed vector-store implementation must be copied.

## 7. Canonical AI turn flow

A customer-facing AI turn must follow this order or an equivalent flow proven by the planner:

```text
native inbound message persisted
 -> duplicate-processing prevention
 -> human-control / opt-out / eligibility check
 -> input guardrail
 -> bounded allowed actions for this turn
 -> recent canonical Chatwoot history
 -> contact + pipeline + proposal context
 -> RAG retrieval
 -> optional durable memory
 -> model invocation
 -> registered tool/action processing
 -> output grounding / validation
 -> persist/send only approved final response through native Chatwoot messaging
 -> usage/evidence/audit record
 -> operational state update / handoff if required
```

Requirements:

- inbound message exists before AI execution;
- provider failure never erases inbound history;
- same inbound message cannot create duplicate agent responses;
- human-controlled conversation suppresses automatic AI replies;
- unvalidated transactional claims must not be sent;
- final persisted outbound content must match delivered content.

## 8. Agent actions and capabilities

The model may interpret, ask questions, retrieve knowledge and request registered actions. It must not have free-form execution authority.

Classify actions equivalently to:

- read-only;
- automatic;
- requires confirmation;
- disabled.

Side-effect actions require:

- server-side schema;
- authorization;
- idempotency;
- correlation;
- audit;
- deterministic executor.

The model must never select arbitrary URL, HTTP method, secret, token, SQL, shell command or webhook destination.

Initial commercial actions should cover behavior equivalent to:

- locate/update contact context;
- move pipeline stage through allowed service;
- create private handoff summary/note;
- request proposal generation;
- request proposal approval/send when allowed;
- emit workflow/cadence signals;
- request human handoff.

## 9. Human handoff and control

Support operational states equivalent to:

- AI active;
- handoff requested;
- awaiting human;
- human active;
- paused;
- closed/resolved;
- authorized return to AI.

Leverage native Chatwoot assignment/status concepts where possible instead of duplicating them, but add explicit AI-control state when native state is insufficient.

On handoff create a private note containing at minimum:

- transfer reason;
- concise conversation summary;
- customer objective;
- qualification fields collected;
- objections;
- pipeline stage;
- proposal status;
- pending actions;
- recommended next step.

Rules:

- human takeover immediately suppresses agent replies;
- applicable pending follow-ups pause/cancel according to cadence policy;
- human outbound messages remain in native Chatwoot history;
- return to AI must be explicit/authorized;
- duplicate takeover/return commands must be idempotent.

## 10. Follow-up cadence engine

Add a deterministic multi-step cadence module integrated with native Chatwoot WhatsApp template sending.

Initial ScanSolo policies:

### Novo Lead

- attempt 1: +2h;
- attempt 2: +24h;
- attempt 3: +48h;
- attempt 4: +96h.

### Em Contato

- 5 attempts;
- initial default: 24h between attempts.

### Em Qualificação

- 7 attempts;
- initial default: 24h between attempts.

### Sending window

- 09:00–20:00;
- timezone: `America/Sao_Paulo`;
- seven days per week.

Required stop/recalculation conditions:

- customer reply;
- partial customer reply: cancel immediate pending send and recalculate remaining eligibility;
- human takeover;
- stage change;
- won;
- lost;
- opt-out;
- manual pause;
- cadence replacement/cancellation;
- template unavailable/not approved;
- automation disabled.

Required engine behavior:

- idempotent enrollment;
- versioned/configurable cadence definition;
- scheduled jobs through the native background-job architecture;
- retry without duplicate sends;
- immutable execution evidence/snapshot sufficient for audit;
- current step and next-attempt visibility;
- pause/resume/cancel;
- manual enrollment only when authorized;
- test/simulation mode;
- stage-specific template mapping;
- sending-window adjustment;
- no LLM-based waiting/timing.

## 11. Meta WhatsApp templates

Chatwoot remains the WhatsApp transport owner.

Cadence steps reference provider templates that are available/approved for the connected WhatsApp inbox.

The final production connection is deferred, therefore implementation must support fake/test template references.

Never mark a follow-up as successfully sent before the native transport accepts the send operation. Capture later delivery/read/failure status when exposed by native Chatwoot events/models.

## 12. Proposal automation

Proposal automation is ScanSolo-specific.

Required conceptual actions:

- `proposal.generate`
- `proposal.approve`
- `proposal.send`

Target flow:

```text
agent collects required fields
 -> deterministic completeness validation
 -> proposal.generate request
 -> registered Make integration
 -> validated result/callback
 -> persist proposal/version/reference/value/artifact metadata
 -> optional human approval
 -> proposal.send
 -> native Chatwoot/WhatsApp delivery request
 -> successful send evidence
 -> stage = Proposta Enviada
 -> post-proposal cadence enrollment
```

Requirements:

- authoritative price/value comes from deterministic integration/service;
- model cannot invent price, discount, total or payment condition;
- generation, approval and send remain separable;
- never claim success before validated integration/send result;
- proposal version/current-reference protection;
- idempotent generate/send callbacks;
- failures are retryable only where safe;
- support a mock proposal provider during development.

## 13. Make integration platform

Use Make as the preferred external integration mechanism for ScanSolo-specific operations.

Do not place Make in the normal message-response path unless a registered action actually requires it.

Requirements:

- registered integration configuration server-side;
- secrets server-side/encrypted;
- structured request schema;
- correlation ID;
- idempotency key;
- signed/authenticated callbacks where technically supported;
- replay protection;
- response schema validation;
- retry/dead-letter/error visibility;
- no arbitrary callback mutation command;
- audit trail.

Initial production use case: proposal generation/send integration currently performed for ScanSolo.

## 14. Security and privacy

At minimum:

- server-side secrets only;
- least privilege;
- authenticated webhooks/callbacks;
- replay protection;
- idempotency for side effects;
- rate limiting where appropriate;
- audit trails;
- attachment safety;
- safe log redaction;
- no arbitrary code/SQL/URL execution by AI;
- no provider token or internal secret in prompts;
- fail closed on ambiguous authorization or callback identity.

## 15. Test mode

A complete isolated test mode is mandatory before production activation.

It must allow testing:

- fake conversations/messages;
- mock LLM responses and/or isolated provider key later;
- RAG retrieval;
- action/tool evidence;
- pipeline transitions;
- human takeover and return;
- cadence scheduling with accelerated/simulated timing where practical;
- fake Meta template references;
- mock Make request/callback;
- mock proposal artifact/value;
- retry and duplicate-event behavior;
- no real WhatsApp send;
- no real customer data requirement;
- no production secrets.

## 16. Deployment target

Target production architecture: Linux VPS + Docker Compose.

Planner must account for the actual current Chatwoot deployment architecture and include as applicable:

- web process;
- Sidekiq worker(s);
- PostgreSQL;
- Redis;
- S3-compatible object storage;
- reverse proxy;
- HTTPS/TLS;
- health checks;
- persistent data;
- database migrations;
- restart policy;
- backup/restore;
- environment variable management;
- log rotation/observability;
- security updates;
- rollback;
- upstream upgrade strategy.

Do not deploy production during autonomous execution.

## 17. Upstream maintainability

This repository must remain maintainable against `chatwoot/chatwoot` upstream.

Prefer:

- isolated modules/namespaces;
- configuration and extension services;
- additive migrations;
- existing events/hooks/jobs;
- reusable Vue components;
- minimal changes to existing native flows.

Avoid unnecessary rewrites of Chatwoot core.

Document every customization with high expected merge-conflict risk.

## 18. Migration from Lexus

Do not migrate production data or disable Lexus during implementation.

Before cutover, create a migration/cutover design for the minimum ScanSolo data required to preserve continuity, including as applicable:

- current contact identity/phone/e-mail;
- active commercial pipeline state;
- required qualification fields;
- relevant proposal state/reference;
- pending cadence state or explicit cancellation/re-enrollment strategy;
- agent prompt/playbook/configuration;
- knowledge sources/documents;
- approved Meta template mappings;
- human ownership/handoff state if needed.

Do not assume all Lexus historical tables must be migrated. Native Chatwoot history after activation becomes the new conversational record.

## 19. Deferred final activation

Implementation must stop before:

- connecting the real ScanSolo WhatsApp number;
- changing the current Meta production webhook;
- setting the production Meta token;
- setting a production OpenAI secret;
- enabling production Make scenarios/callbacks;
- configuring real proposal API credentials;
- switching final DNS under `scansolo.com.br`;
- sending a real customer message;
- migrating/cutting over production data;
- disabling ScanSolo in Lexus;
- production deploy without explicit approval.

## 20. Acceptance outcome before cutover

The isolated system must demonstrate:

1. fake inbound message persists in native Chatwoot flow;
2. AI processes one turn exactly once;
3. agent uses canonical conversation history;
4. RAG retrieval returns evidence;
5. guardrails/action permissions are enforced;
6. pipeline state changes correctly and Kanban reflects it;
7. AI handoff creates private summary and suppresses further AI;
8. authorized return to AI works;
9. Novo Lead cadence schedules +2h/+24h/+48h/+96h correctly;
10. customer response cancels/recalculates applicable pending cadence work;
11. human takeover pauses/stops applicable cadence work;
12. stage change recalculates/replaces cadence according to policy;
13. fake Meta template send runs through native Chatwoot messaging path;
14. mock proposal generation runs through Make-compatible contract;
15. proposal cannot report sent before successful send evidence;
16. successful proposal send moves stage and enrolls configured cadence;
17. duplicate jobs/webhooks/callbacks do not duplicate side effects;
18. relevant operations are auditable;
19. no production token/key/number is required for the test suite;
20. Docker-based staging deployment and rollback instructions are documented before production activation.

## 21. Phase planning requirements

Every task generated in `PHASES.md` must include:

- stable identifier;
- clear title;
- acceptance criteria;
- explicit tests with repository path/command;
- dependencies;
- no implicit production side effect.

The planner must create separate human gates for provider activation, VPS production deployment, production migrations, DNS, real WhatsApp, real OpenAI, real Make, real proposal API, Lexus production cutover and secrets.
