# ScanSolo End-to-End Flow

## Objective

Define the operational flow the custom Chatwoot platform must provide before the real ScanSolo integrations are connected.

## 1. Lead entry

```text
ScanSolo website
 -> customer clicks WhatsApp CTA
 -> WhatsApp
 -> Meta Cloud API
 -> ScanSolo Chatwoot inbox
```

Chatwoot owns channel transport, native contact resolution, conversation/message persistence and the human inbox.

## 2. First inbound message

```text
native Chatwoot inbound message persisted
 -> AI eligibility check
 -> duplicate-turn protection
 -> human-control/opt-out check
 -> AI turn job
```

The AI must never run before the inbound message exists in native Chatwoot history.

## 3. AI turn

```text
Chatwoot conversation history
 + contact context
 + commercial pipeline context
 + qualification state
 + knowledge/RAG
 + optional durable memory
 + agent configuration/playbook
 + allowed actions for this turn
        |
        v
      LLM
        |
        v
output validation / grounding
        |
        v
native Chatwoot outbound message
```

If the answer is not approved by output validation, it is not sent as a trusted customer-facing response.

## 4. Qualification and pipeline

Initial authoritative stages:

```text
Novo Lead
 -> Em Contato
 -> Em Qualificação
 -> Qualificado
 -> Proposta Enviada
 -> Negociação
 -> Ganho / Perdido
```

Example transitions:

- real conversation established -> Em Contato;
- qualification questions begin -> Em Qualificação;
- configured required fields complete -> Qualificado;
- proposal send confirmed -> Proposta Enviada;
- human may move into Negociação through allowed action/rule;
- won/lost terminates applicable automated commercial follow-up.

The Kanban is a visual projection of authoritative persisted stage state.

## 5. Human handoff

```text
AI detects/request handoff
 -> suppress further automatic AI response
 -> create private handoff summary
 -> route/assign using native Chatwoot team/agent behavior
 -> human becomes controller
 -> cadence pauses/stops according to policy
```

Private note includes:

- reason;
- summary;
- objective;
- collected fields;
- objections;
- pipeline stage;
- proposal state;
- pending actions;
- suggested next step.

Return to AI must be explicit and authorized.

## 6. Follow-up cadences

### Novo Lead

```text
+2h -> template 1
+24h -> template 2
+48h -> template 3
+96h -> template 4
```

### Em Contato

```text
5 attempts, initially 24h apart
```

### Em Qualificação

```text
7 attempts, initially 24h apart
```

### Sending window

```text
09:00–20:00 America/Sao_Paulo
7 days/week
```

### Re-evaluation

Before each scheduled send:

```text
customer replied?        -> stop/recalculate
human owns conversation? -> pause/stop
stage changed?           -> cancel/re-enroll under new policy
won/lost?                -> stop
opt-out?                 -> stop
cadence paused?          -> do not send
template valid/approved? -> otherwise fail safely
already executed?        -> idempotent no-op
```

Templates are native Meta/WhatsApp templates made available through Chatwoot. The custom cadence engine controls timing/state; it does not invent message templates.

## 7. Proposal

```text
Agent gathers configured proposal fields
 -> deterministic completeness check
 -> proposal.generate
 -> registered Make request
 -> proposal service/API
 -> Make callback
 -> callback validation
 -> persist proposal version/reference/value/artifact
 -> approval when required
 -> proposal.send
 -> native Chatwoot delivery request
 -> send accepted/confirmed
 -> Pipeline = Proposta Enviada
 -> post-proposal cadence
```

The model may collect/normalize data but cannot calculate or invent the authoritative commercial value.

## 8. Make usage

Make is not in every conversation turn.

Use it only for registered external operations, initially proposal-related flows:

```text
Chatwoot custom action
 -> integration service
 -> Make
 -> external calculation/generation
 -> validated callback
 -> bounded persisted result/action
```

## 9. Knowledge / RAG

Knowledge center manages:

- ScanSolo company information;
- services;
- FAQ;
- commercial/process documents;
- indexed sources;
- retrieval evidence.

Current upstream production compose uses `pgvector/pgvector:pg16`; after code inspection the planner should evaluate whether using the existing PostgreSQL/pgvector stack is the cleanest Community-compatible RAG implementation, without copying proprietary Captain backend code.

## 10. Human operating experience

The ScanSolo team should work in one application:

```text
Conversas
Contatos
Pipeline
Agente de IA
Conhecimento
Follow-ups
Propostas
Equipe
Templates
Automação e integrações
Execuções e auditoria
```

They should not need to open Lexus CRM after final cutover.

## 11. Final provider activation

Only after all mock/staging behavior passes:

1. production VPS approved;
2. final ScanSolo subdomain/DNS configured;
3. OpenAI production key configured;
4. Make production integration configured;
5. proposal production credentials configured;
6. Meta production credentials configured;
7. real ScanSolo WhatsApp number connected;
8. current Lexus ScanSolo automation paused;
9. Meta webhook ownership switched;
10. controlled end-to-end test;
11. real traffic activated.
