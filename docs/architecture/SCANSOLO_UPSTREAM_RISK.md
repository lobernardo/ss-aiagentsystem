# ScanSolo Upstream Merge-Conflict Risk

## Purpose

This document tracks every ScanSolo customization that touches a **pre-existing** upstream
(`chatwoot/chatwoot`) file rather than living entirely under an isolated `ScanSolo::`/`scan_solo`
namespace. Per `docs/architecture/ADR-001-chatwoot-scansolo-platform.md` ("Native Chatwoot
responsibilities" / Upstream strategy) and RF-97, every such touch must be listed here with its
rationale, so a future upstream sync can locate and re-apply it deliberately instead of discovering
it as a surprise merge conflict.

The great majority of ScanSolo code lives under `app/**/scan_solo/**`, `app/controllers/webhooks/scan_solo/**`,
`app/javascript/dashboard/routes/dashboard/scansolo/**`, `docs/**`, and `spec/**scan_solo**` — none of
those are listed below, because they are net-new files with zero pre-existing upstream content to
conflict with.

## High-risk customizations

### 1. `config/routes.rb`

- **What changed**: an additive `namespace :scan_solo do ... end` block nested under the existing
  `api/v1/accounts/:account_id` namespace (mirrors the established resource-nesting convention used
  by every other Chatwoot API namespace), plus one additive top-level route,
  `post 'webhooks/scan_solo/make', to: 'webhooks/scan_solo/make#process_callback'`.
- **Why it is high-risk**: `config/routes.rb` is a single shared file edited by nearly every upstream
  PR that adds an endpoint. Any upstream change to a line near the ScanSolo block (or to the
  `api/v1/accounts/:account_id` namespace itself) can produce a textual merge conflict even though
  the ScanSolo route additions are semantically independent.
  - **Mitigation**: the ScanSolo `namespace :scan_solo do` block and the ScanSolo webhook route are
    each self-contained and additive only — no existing route, controller mapping, or constraint was
    removed or reordered. On conflict, re-applying is mechanical: re-insert the block/line unchanged.

### 2. `app/models/account.rb` — `scansolo_feature_flags` bit column (FlagShihTzu)

- **What changed**: `db/migrate/20260917231850_add_scansolo_enabled_flag_to_accounts.rb` adds a new,
  dedicated `scansolo_feature_flags` bigint column to the pre-existing `accounts` table (additive
  `add_column`, `default: 0, null: false` — see `spec/db/scansolo_migrations_spec.rb`), and
  `Account` declares `has_flags 1 => :scansolo_enabled, :column => 'scansolo_feature_flags'`
  immediately below the pre-existing `feature_flags`/`feature_flags_ext_1` `has_flags` declarations.
- **Why it is high-risk**: `app/models/account.rb` is a large, frequently-edited upstream model.
  Adding a `has_flags` declaration next to the native `feature_flags` one risks a textual conflict on
  every upstream PR that touches nearby lines, and — more importantly — a **bit-index collision** if
  a careless merge were to fold the new flag into the native `feature_flags`/`feature_flags_ext_1`
  column instead of its own dedicated `scansolo_feature_flags` column.
  - **Mitigation**: the ScanSolo flag deliberately lives in its **own** bit column
    (`scansolo_feature_flags`), never sharing bit space with `feature_flags`/`feature_flags_ext_1`
    (which are owned by `Featurable`/`config/features.yml`). This means an upstream merge can never
    silently reassign or overwrite a ScanSolo bit by reflowing the native feature-flag enum — the
    worst case is a textual conflict on the `has_flags` declaration itself, which is trivial to
    re-apply.

### 3. `app/models/conversation.rb` / `app/models/message.rb` — schema-annotation churn

- **What changed**: no ScanSolo business logic was added to either file. The only diffs are
  `annotate`-generated schema-comment refreshes (index list at the top of each file) that occur
  automatically whenever *any* migration adds an index to the `conversations`/`messages` tables —
  including migrations unrelated to ScanSolo.
- **Why it is high-risk**: these are large, foundational upstream models edited by most Chatwoot
  PRs. Even a comment-only diff can produce a textual merge conflict on upstream sync.
  - **Mitigation**: none of this plan's `ScanSolo::` code adds a column, association, or method to
    `Conversation`/`Message` — conversation/message behavior is extended exclusively via the
    `ScanSolo::ConversationExtension` join model (T07) and the `ScanSolo::ConversationListener`
    (see below), never by editing these classes directly. On conflict, the resolution is always to
    keep upstream's annotation and re-run `annotate` locally — there is no ScanSolo-owned logic to
    lose.

### 4. `app/dispatchers/async_dispatcher.rb` — listener registration

- **What changed**: `ScanSolo::ConversationListener.instance` was appended to the existing
  `#listeners` array, alongside the native `AutomationRuleListener`, `CampaignListener`,
  `NotificationListener`, etc.
- **Why it is high-risk**: `#listeners` is a shared array; an upstream PR that adds/reorders a
  listener touches the same lines.
  - **Mitigation**: the addition is a single appended array entry with no reordering of existing
    entries — trivially re-appliable on conflict. See "Native event/job reuse" below for why this is
    the *only* integration point ScanSolo needs with the dispatch layer.

## Native event/job reuse (RF-96)

RF-96 requires every ScanSolo domain event to flow through the existing `Dispatcher`/`AsyncDispatcher`
seam rather than a new pub/sub mechanism. This is enforced two ways:

1. **By construction**: `ScanSolo::ConversationListener` (`app/services/scan_solo/conversation_listener.rb`)
   is a `BaseListener` subclass — the same base class every native Chatwoot listener
   (`AutomationRuleListener`, `NotificationListener`, `WebhookListener`, ...) inherits from — registered
   in `AsyncDispatcher#listeners` (see item 4 above). It receives the native `message.created` event,
   applies ScanSolo pipeline bookkeeping, and enqueues `ScanSolo::AiTurnJob` via standard
   `ActiveJob`/Sidekiq (`perform_later`), the same job-queuing mechanism used by every other Chatwoot
   background job. No new event bus, message broker, or subscription registry was introduced.
2. **By repository search**: `spec/lib/scansolo_dispatcher_reuse_spec.rb` asserts that no file under
   `app/**/scan_solo/**` (or `lib/**/scan_solo/**`) defines a class named like a pub/sub/event-bus
   primitive (`*Bus`, `*Emitter`, `*Broadcaster`, `*PubSub`, `*EventBus`, `*MessageBus`), and that
   `ScanSolo::ConversationListener` is registered on `AsyncDispatcher`.

## Summary table

| File | Type of touch | Risk | Re-apply cost on conflict |
|---|---|---|---|
| `config/routes.rb` | additive namespace + route | Medium | Trivial (re-insert block) |
| `app/models/account.rb` | additive `has_flags` on dedicated column | Medium | Trivial (re-insert declaration) |
| `app/models/conversation.rb` | annotation-only (no logic) | Low | Trivial (re-run `annotate`) |
| `app/models/message.rb` | annotation-only (no logic) | Low | Trivial (re-run `annotate`) |
| `app/dispatchers/async_dispatcher.rb` | additive array entry | Low | Trivial (re-append entry) |
