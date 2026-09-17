# Chatwoot Upstream Capability Notes

## Baseline inspected

- Upstream: `chatwoot/chatwoot`
- Branch: `develop`
- Baseline inspected on 2026-09-16: `5b7038b950b763e230df2d544df9b87b8752fef3`

The bootstrap script records the actual fetched commit at execution time; that value is authoritative for the local imported code.

## Licensing

Upstream root `LICENSE` states:

- content outside restricted areas such as `enterprise/` is available under MIT Expat;
- `enterprise/` has its own Chatwoot Enterprise license.

Project rule:

- custom ScanSolo implementation must be based on Community/MIT code and independently implemented requirements;
- do not derive/copy implementation from proprietary `enterprise/` files;
- the imported upstream source may contain the upstream `enterprise/` directory as part of the official repository layout, but the ScanSolo Community product must not enable or depend on those proprietary features without a deliberate license decision.

## Branding foundation

Current `config/installation_config.yml` contains installation-wide settings including:

- `INSTALLATION_NAME`;
- `LOGO_THUMBNAIL`;
- `LOGO`;
- `LOGO_DARK`;
- `BRAND_URL`;
- `WIDGET_BRAND_URL`;
- `BRAND_NAME`;
- `TERMS_URL`;
- `PRIVACY_URL`;
- `DISPLAY_MANIFEST`.

This provides a native configuration seam for ScanSolo branding. Final assets/hostname are intentionally deferred.

## WhatsApp

Current installation configuration contains native WhatsApp Cloud/Meta configuration such as:

- `WHATSAPP_APP_ID`;
- `WHATSAPP_CONFIGURATION_ID`;
- `WHATSAPP_APP_SECRET`;
- `WHATSAPP_API_VERSION`.

The final real number/token/webhook remain deferred until cutover.

## AgentBot

AgentBot infrastructure is present in Community code.

Relevant inspected paths include:

- `app/listeners/agent_bot_listener.rb`;
- `spec/listeners/agent_bot_listener_spec.rb`.

The listener emits bot events including `message_created` and uses an AgentBot `outgoing_url`, secret and delivery identifier through background webhook jobs.

This is a reusable Community integration seam for AI/bot behavior and must be considered by the planner before introducing parallel webhook infrastructure.

## Captain / AI caution

The current upstream repository contains Captain-related UI, configuration and migrations outside `enterprise/`, but important Captain backend models/controllers/builders are present under `enterprise/`.

Example inspected proprietary path:

- `enterprise/app/models/captain/assistant.rb`.

Examples of non-enterprise Captain-related surfaces include:

- `app/javascript/dashboard/store/captain/assistant.js`;
- `app/javascript/dashboard/api/captain/assistant.js`;
- `app/javascript/dashboard/components-next/captain/assistant/...`;
- database migrations for Captain tables;
- Captain OpenAI/embedding configuration keys in `config/installation_config.yml`.

Therefore the planner must **not assume Captain backend is a free Community agent engine**.

Required approach:

1. inspect exact dependencies after importing upstream;
2. reuse generic Community UI/components only when they are not dependent on proprietary behavior and license use is clear;
3. independently implement the ScanSolo AI Agent Center from approved requirements and Lexus behavior references where required;
4. do not copy algorithms, service/model code or API implementation from `enterprise/`.

## Upstream-first development rule

Before implementing any custom feature, planner/executor must first answer:

1. Does Community Chatwoot already provide this behavior?
2. Is there an event/service/job/API extension seam we can reuse?
3. Can the ScanSolo behavior be additive instead of modifying the native core path?
4. Is the tempting upstream implementation under `enterprise/`? If yes, stop and independently design from requirements.

This rule applies especially to:

- AI/Captain-like functionality;
- automation;
- WhatsApp templates;
- assignment/handoff;
- custom attributes;
- webhooks;
- reports/audit;
- contact/conversation data.
