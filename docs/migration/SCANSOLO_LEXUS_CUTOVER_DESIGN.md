# ScanSolo ⇄ Lexus Migration/Cutover Design

## Status

**Design only.** No code in this repository performs a live read or write against
the Lexus production system, and none will until the `T89` human-approval gate
(RF-99, RF-100) is explicitly checked by a human outside the automated run. This
document exists to satisfy RF-98: a documented migration/cutover design, with an
explicit decision per continuity-data category, produced *before* cutover.

## Purpose and scope

Per `docs/migration/LEXUS_REFERENCE_MAP.md` and
`docs/migration/RUNTIME_DATA_INVENTORY.md`, this document covers the minimum
ScanSolo continuity data needed to move operation from the legacy Lexus CRM
runtime to the new Chatwoot-based ScanSolo extension layer without losing
in-flight commercial state. For each category below the decision is exactly one
of:

- **Migrate** — import the Lexus value(s) as-is (or with a mechanical field
  mapping) into the new system's native representation.
- **Re-derive** — do not copy the Lexus value directly; instead reconstruct
  equivalent state in the new system using the new system's own deterministic
  services, using Lexus data only as an input/checklist.
- **Explicitly discard** — do not carry the value forward at all; the new
  system starts this piece of state fresh at cutover.

Every category maps to a model or service already implemented in this
codebase (`app/models/scan_solo/**`, `app/services/scan_solo/**`), so decisions
below are grounded in the actual target schema, not a hypothetical one.

## Cutover ordering

Categories are not independent — several foreign-key into ones migrated
earlier. The design assumes cutover proceeds in this order:

1. Contact identity
2. Agent configuration
3. Knowledge sources
4. Active pipeline state
5. Qualification fields
6. Proposal state/reference
7. Approved template mappings
8. Cadence state / re-enrollment strategy
9. Human ownership/handoff state

Contact identity migrates first because `ScanSolo::PipelineOpportunity`,
`ScanSolo::Proposal`, and every other ScanSolo record foreign-keys to a
native `Contact`/`Conversation` row. Human ownership/handoff state migrates
last because it depends on the pipeline, proposal, and cadence state already
being in place to build an accurate handoff note (per
`ScanSolo::Handoff::HandoffService`, RF-51).

---

### 1. Contact identity

**Decision: Migrate**

Native Chatwoot's `Contact` model (`identifier`, `phone_number`, `email`,
`name`) is the anchor every ScanSolo record foreign-keys to
(`PipelineOpportunity#contact_id`, qualification fields stored on
`Contact#custom_attributes`). Lexus's contact identity (WhatsApp
E.164 phone number as the primary matching key, name, email where present)
must be imported into native `Contact` rows, deduplicated by
`phone_number` per account (matching the existing unique index
`uniq_identifier_per_account_contact` / `index_contacts_on_phone_number_and_account_id`).
No new ScanSolo-owned contact table is created — Lexus contact identity
resolves onto the same native `Contact` record already used by the
WhatsApp inbox for message delivery.

Rationale: duplicating contact identity in a parallel ScanSolo table would
violate RF-95/RF-96 (no parallel core entity) and `LEXUS_REFERENCE_MAP.md`
§12's explicit rule against "duplicated Contact/Conversation/Message
entities."

### 2. Agent configuration

**Decision: Migrate (content) with mandatory re-publish, never auto-publish**

The Lexus `AiAgentService` configuration fields (name, role, objective,
persona, playbook, general instructions, tone, service rules, restricted
information, transfer criteria, response limits, forbidden subjects,
service/channel behavior) map directly onto `ScanSolo::AiAgentConfig::FIELDS`.
The content of the currently-active/published Lexus agent version is
imported as a **draft** row (`ScanSolo::AiAgentConfig.draft_for!`), never
written directly into a published row.

Rationale: `PublishService#call` (T19) is the only path that may make a
config live (RF-22); importing Lexus content straight into
`published_version` would bypass that atomic-swap invariant and could put a
partially-reviewed configuration into a live conversation turn without
human review. A human must explicitly trigger `PublishService` after
reviewing the imported draft.

The `enabled_actions`/autonomy-policy concept from Lexus's
`AgentCapabilityService` is **explicitly discarded** as a literal migration —
ScanSolo's action set (`ScanSolo::Actions::Registry`) is intentionally
smaller than Lexus's full `ActionCatalog` per
`LEXUS_REFERENCE_MAP.md` §4 ("Do not reproduce the full Lexus CRM tool
catalog"), so there is no 1:1 field to migrate; the new registry's fixed
action set is used as-is.

### 3. Knowledge sources

**Decision: Re-derive (re-ingest content; discard vectors)**

Lexus's existing vector-store embeddings are **not** migrated — the target
platform uses a self-hosted `pgvector`/`neighbor` stack
(`ScanSolo::KnowledgeChunk#has_neighbors`), which is architecturally
different from whatever embedding model/provider Lexus's OpenAI-managed
vector store used, per `LEXUS_REFERENCE_MAP.md` §5 ("Do not assume an
OpenAI-managed vector store is mandatory").

What migrates is the **checklist of active source metadata**: for every
enabled Lexus knowledge entry, record `title`, `source_type`
(document/faq/company_info), `origin`, and `enabled` status, then re-ingest
the underlying document/FAQ/company-info *content* through
`ScanSolo::Knowledge::IngestionService` (T25), which regenerates chunks and
embeddings natively. Documents already stored as files are re-uploaded
through the native `ActiveStorage` attachment path (`has_one_attached
:file`), never copied at the storage-provider level (RF-90).

Disabled/archived Lexus knowledge entries are **explicitly discarded** —
they were already excluded from retrieval in the source system
(`RF-30`-equivalent behavior) and re-ingesting them would only add noise.

### 4. Active pipeline state

**Decision: Migrate (open opportunities only); discard closed-deal history**

Only Lexus deals **not** in a terminal state map onto a new
`ScanSolo::PipelineOpportunity` row, with `stage` mapped onto the fixed
8-value enum (`novo_lead, em_contato, em_qualificacao, qualificado,
proposta_enviada, negociacao, ganho, perdido`, RF-06) and `owner_id` mapped
onto the corresponding native `User`. `last_customer_interaction_at` is
migrated from the most recent inbound-message timestamp on the matching
Lexus conversation, since it drives the stale-indicator/`RF-11` behavior
immediately after cutover.

Lexus deals already `ganho`/`perdido` (terminal, per T12's terminal-state
rule) and their full stage-history are **explicitly discarded** — they are
commercially closed, and the new system's `PipelineStageEvent` log (RF-07)
is a fresh append-only ledger starting at cutover, not a backfilled history.
Backfilling terminal deals would create data the new system's own
transition service never produced and can never explain.

### 5. Qualification fields

**Decision: Migrate values, filtered through the new allowlist**

Lexus qualification field values transfer onto the matching migrated
`Contact#custom_attributes`, but **only** for keys present in the
newly-published `ScanSolo::AiAgentConfig#required_qualification_fields`
allowlist for that account — exactly the same filter
`ScanSolo::Actions::QualificationFieldAction` applies to every live update
(`allowed_fields = ... slice(*allowed_fields)`). Any Lexus-collected field
that is not on the new allowlist is **explicitly discarded**: the new
Agent Center config is the single source of truth for which fields are
"allowed" (RF-48), and importing an unlisted field would create contact
data the running system's own action can never have written, breaking the
invariant that only allowlisted keys ever appear.

Migrating these values does **not** itself trigger the automatic
`em_contato → em_qualificacao`/`em_qualificacao → qualificado` transitions
(RF-15/RF-16) — pipeline stage was already set explicitly in category 4
above, and re-running the auto-transition side effect during a bulk import
would risk moving an opportunity to a stage its Lexus record never reached.

### 6. Proposal state/reference

**Decision: Migrate current version only; discard version history**

For opportunities migrated as still-open in category 4 that have an active
Lexus proposal, only the **current/latest** proposal state is imported: a
`ScanSolo::Proposal` row plus exactly one `ScanSolo::ProposalVersion` with
`is_current: true`, populated from Lexus's `reference`, `value`, `currency`,
and delivery/approval status. This satisfies the DB partial-unique
"one current version" invariant (RF-77) trivially, since only one version
is ever created.

Earlier proposal revisions/history are **explicitly discarded** — RF-76's
"no invented price" guarantee only binds the live `GenerateService`/
`SuccessHandler` write path going forward; there is no equivalent write
path in this design that needs old superseded versions to reason about, and
carrying them forward would require inventing a `ScanSolo::Proposal::
GenerateService` invocation that never actually happened for historical
rows.

If an opportunity's only Lexus proposal is still mid-flight with an
external Make/proposal-API request outstanding, that pending state is
**explicitly discarded**: no in-flight external correlation ID is
transplanted into `ScanSolo::MakeRequest`/`ScanSolo::MakeCallback`, since
this system's idempotency/correlation guarantees (RF-75) only hold for
requests it originated itself. The proposal must be regenerated through the
new `ScanSolo::Proposal::GenerateService` after cutover instead.

### 7. Approved template mappings

**Decision: Migrate as an external Meta-side registration, not a DB write**

`ScanSolo::CadenceDefinition#template_reference_for` derives a fixed name
(`scansolo_cadence_#{stage}_v#{version}_step#{step}`) rather than storing a
lookup row, and `ScanSolo::Cadence::TemplateAvailabilityGuard` validates a
due attempt's template only by checking whether a `Channel::Whatsapp`'s
native `message_templates` array (populated by Meta's own template sync)
contains an entry with that exact `name` and `status == "approved"`. There
is therefore no ScanSolo table to migrate template mappings into.

What must happen before the `T86` WhatsApp-connection gate opens is an
**external, non-code action**: register (or rename an existing approved)
Meta Business Manager template for every derived
`template_reference_for(step)` name across all three seeded cadence
schedules (Novo Lead ×4, Em Contato ×5, Em Qualificação ×7) plus any
proposal-send template, using the current Lexus-approved template content
as the source copy so customers keep receiving recognizable message
wording. Until that registration exists, `TemplateAvailabilityGuard`
correctly and safely skips the send (`reason: 'template_unavailable'`) —
this is the designed fail-safe, not a bug to route around.

Lexus's own template *identifiers*/provider IDs are **explicitly discarded**
— they are Lexus-provider-specific and have no field in the new schema;
only the human-readable template *name/content* is carried forward into the
new Meta registration.

### 8. Cadence state / re-enrollment strategy

**Decision: Re-derive via fresh enrollment; migrate only stop/opt-out flags**

Lexus's exact next-scheduled-attempt timestamps and step counters are
**not** copied into `ScanSolo::CadenceEnrollment`/`ScanSolo::CadenceAttempt`
— the new engine's offsets (`+2h/+24h/+48h/+96h` for Novo Lead, 24h-apart
for Em Contato and Em Qualificação, RF-57) are versioned independently of
whatever schedule Lexus was running, so a transplanted "next attempt in
6 hours" value would not correspond to any real offset in the new
`CadenceDefinition`. Instead, at cutover, every migrated open opportunity
(category 4) that Lexus shows as actively enrolled in a stage cadence is
re-enrolled from scratch through the existing idempotent
`ScanSolo::Cadence::EnrollmentService` (RF-59) against the current stage's
`CadenceDefinition.current_for(stage)`, effectively restarting that
opportunity's applicable schedule from the cutover moment.

Lexus's **stop-condition state is migrated**, not discarded: an opportunity
that Lexus shows as opted-out, manually paused, or already at its final
cadence step is enrolled with an immediate `paused_at`/`cancelled` status
(mirroring `ScanSolo::CadenceEnrollment#status`) rather than left to send a
fresh first attempt — RF-65's stop/recalculate rule must be honored for
carried-over state, not only for state produced after cutover, or a
customer who already opted out in Lexus would receive an unwanted message
from the new engine.

Full attempt-history evidence rows are **explicitly discarded** — they are
observability data for the old engine's own delivery attempts and have no
matching `ScanSolo::CadenceAttempt` row to attach to, since the new
enrollment created in this step starts its own step counter at zero.

### 9. Human ownership/handoff state

**Decision: Migrate ownership; explicitly discard/reset in-flight handoff state**

Current human routing/ownership (which agent or team is responsible for an
active conversation) is **migrated**, mapped onto native Chatwoot
`Conversation#assignee_id`/team assignment — fields Chatwoot already owns,
per RF-95/RF-96 (no parallel ownership model).

Lexus's in-flight `ConversationStateService` value
(`agent_active / handoff_requested / awaiting_human / human_active / paused
/ closed`) is **explicitly discarded** rather than mechanically mapped onto
`ScanSolo::ConversationExtension#ai_control_state`. A wrong 1:1 mapping is
safety-critical to get wrong in the unsafe direction: if a conversation
Lexus shows mid-handoff were imported as `ai_active`, the new AI turn
pipeline could resume replying automatically on a conversation a human was
actively working. Instead, every migrated conversation with a live human
owner assigned in Lexus is initialized to `human_active`
(`ScanSolo::ConversationExtension#ai_control_state`), the conservative
default that keeps AI replies suppressed until a human explicitly runs
`ScanSolo::Handoff::ReturnToAiService` (T42) to hand it back — never the
reverse. Conversations Lexus shows as fully bot-owned with no human
assignment are initialized to `ai_active`.

For every conversation initialized to `human_active` by this migration, one
private note is created via the same nine-element structure
`ScanSolo::Handoff::HandoffService` already produces on a live handoff
(transfer reason, summary, customer objective, qualification fields,
objections, pipeline stage, proposal status, pending actions, recommended
next step, RF-51) — sourced from the corresponding Lexus record — so the
receiving human agent has full context without needing Lexus access after
cutover.

---

## Decision summary

| # | Category | Decision |
|---|----------|----------|
| 1 | Contact identity | Migrate |
| 2 | Agent configuration | Migrate content (draft only; re-publish required) |
| 3 | Knowledge sources | Re-derive (re-ingest content; discard vectors) |
| 4 | Active pipeline state | Migrate (open only); discard closed-deal history |
| 5 | Qualification fields | Migrate (filtered through new allowlist) |
| 6 | Proposal state/reference | Migrate current version only; discard history |
| 7 | Approved template mappings | Migrate as external Meta registration (no DB write) |
| 8 | Cadence state / re-enrollment strategy | Re-derive via fresh enrollment; migrate stop/opt-out flags |
| 9 | Human ownership/handoff state | Migrate ownership; discard/reset in-flight handoff state |

## Non-goals / explicit exclusions (RF-99)

No task in this plan performs a live read or write against the Lexus
production database, API, or file storage. Every "migrate" decision above
describes the target shape of an eventual, separately-approved migration
script/runbook — none of that script exists yet, and none may run before
the `T89` human-approval gate is checked. This document is the design that
such a future migration script must follow; it is not itself an executable
migration.
