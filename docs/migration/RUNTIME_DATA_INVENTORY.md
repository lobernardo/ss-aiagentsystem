# ScanSolo Runtime Data Inventory

## Purpose

Separate **code/configuration we can build now** from **current production values that must only be extracted/configured during the final migration**.

This prevents the new repository from depending on production secrets or stale assumptions.

## Already encoded as product requirements

The new system can be fully implemented and tested before production values are supplied for:

- conversational inbox/human service;
- pipeline stages and Kanban;
- AI Agent Center fields;
- knowledge/RAG management;
- handoff behavior;
- follow-up cadence engine;
- ScanSolo cadence timing rules;
- proposal generate/approve/send lifecycle;
- Make request/callback contract pattern;
- idempotency/correlation/audit;
- isolated test mode;
- VPS/Docker Compose architecture;
- final cutover gates.

## Production/runtime values intentionally NOT committed to Git

### Meta / WhatsApp

- real WABA identifier;
- real Phone Number ID;
- Meta app ID/secret where required;
- permanent/system-user access token;
- webhook verify secrets;
- current production webhook ownership;
- exact approved template provider identifiers/status at cutover.

### OpenAI / AI provider

- production API key;
- final production model selection;
- any provider organization/project identifiers;
- production cost/billing limits.

### Make / proposal

- production Make scenario URL/identifier;
- callback secret/HMAC material;
- proposal service/API credentials;
- production artifact/storage destinations;
- authoritative commercial calculation configuration not stored safely in source.

### Domain / infrastructure

- final application hostname under `scansolo.com.br`;
- DNS records;
- VPS IP/provider credentials;
- TLS/private keys;
- PostgreSQL production password;
- Redis production password;
- object-storage production credentials;
- SMTP production credentials if used;
- backup destination credentials;
- monitoring/alert secrets.

## Current Lexus ScanSolo data to inventory before cutover

These values may live in the Lexus production database/configuration rather than the repository and therefore are **not confirmed by source code alone**.

Before migration, export/verify the current effective values for:

### Agent configuration

- active/published ScanSolo agent version;
- agent name;
- role/objective;
- persona;
- general instructions;
- playbook;
- service rules;
- tone;
- transfer criteria;
- restricted information;
- forbidden topics;
- response limits;
- service/channel behavior;
- enabled actions/capabilities and autonomy policies.

### Knowledge

- active knowledge collections;
- documents/files;
- FAQ/service information;
- indexing status;
- references that must be re-ingested in the new RAG system.

### Pipeline

- effective stage list/order used by ScanSolo at cutover;
- active opportunities and their stages;
- owner/responsible user where continuity is required;
- qualification fields used by current automation.

### Follow-up templates/cadences

- current approved Meta template names/languages/provider IDs;
- exact stage-to-template mapping;
- any final cadence timing changes made after this requirements document;
- active cadence enrollments and next scheduled attempt;
- paused/cancelled state;
- current stop-condition configuration.

### Proposal

- current registered ScanSolo proposal action schema;
- required input fields;
- current Make scenario contract;
- approval policy;
- active proposal versions/references that must remain actionable;
- current send/delivery mechanism;
- any post-proposal cadence mapping.

### Human service

- current human routing/ownership policy;
- current active human-controlled conversations that need operational continuity;
- handoff/return rules actually enabled at cutover.

## Migration rule

Do not assume repository defaults equal production runtime values.

At final migration:

1. read the current ScanSolo runtime configuration from the authoritative current system;
2. compare with the approved new-system configuration;
3. explicitly resolve differences;
4. import only approved operational state;
5. validate before switching traffic.

## Secrets rule

Secrets must be entered only into the target production secret/environment management system.

Never place real values in:

- this repository;
- bc-harness input;
- SPEC/PLAN/PHASES;
- prompts;
- issue comments;
- logs;
- test fixtures.
