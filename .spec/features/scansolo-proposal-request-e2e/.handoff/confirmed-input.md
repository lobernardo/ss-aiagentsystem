# Confirmed input — scansolo-proposal-request-e2e (slice 2 of 4)

Tier: standard. Extends `.spec/features/scansolo-agent-lead-state/` (slice 1, implemented) and the proposal module from `.spec/features/scansolo-production-complete/` (CT-05/CT-06, `asyncapi.yaml`).

## Summary
Connect a completed `LeadState` to the EXISTING Make/Drive proposal flow (scenarios `ScanSOLO_Proposta_Entrada` + `Aprovacao_Gate_Processor`, Google Docs template, approval Google Form) through approval and delivery to the client. Reuse what exists; no new architecture, no general UI, no follow-ups.

## Acceptance criteria (confirmed by the developer)
1. (D1) Automatic trigger: when qualification completes with `next_action = proposta` and the proposal integration is configured, a post-commit job calls `GenerateService` exactly once per opportunity. Uniqueness is enforced in the database (not an in-memory lock). Existing proposal → no-op; reopening qualification never generates a new version (new versions are manual). Generates the draft only; the human approval gate stays on.
2. (D2) Payload: the Make `qualification` payload adds `projeto` (from `cliente_final`), `email_envio_proposta`, `emails_copia_proposta`, `link_local`, keeping the current keys. Contract defined in one place (`FieldResolver::MAKE_KEYS` + asyncapi).
3. (D3) Send is a single action: one `send` call, one `idempotency_key`, one `sent` state. E-mail with PDF (sent by Make) is the formal document and primary channel, always; its success callback marks `sent` and moves the stage to `proposta_enviada`. Afterwards a short WhatsApp notice with the link is sent; WhatsApp failure is logged/audited and never reverts or blocks `sent`. No dynamic channel priority.
4. (D3) The lead must have an e-mail: a destination e-mail is required for proposal generation; the agent asks for it when missing.
5. (D4) Sender/recipients: e-mail to the client is sent from `atendimento.comercial@scansolo.com.br` (account connected in Make). To = `email_envio_proposta`, else the lead `email`. Cc = `comercial@scansolo.com.br` always + `emails_copia_proposta`.
6. Failure handling: a `failure` callback for `generate` or `send` moves the version to `failed` with `error_code`; `retryable` failures follow the existing retry/dead-letter policy. Docs/Drive/e-mail failures inside Make always produce a failure callback, never silence.
7. (D5) Make adjustments are part of the slice, in a separate phase, each with developer approval, with a blueprint export as backup before changing any scenario. Entrada: idempotency check, failure callbacks, `pv_` validation, JSON built with escaping, recipient/cc. Gate: authentication + failure callback. Deactivate `Lexus_ScanSolo_Proposta_v2` and legacy scenarios, remove the Gate "fluxo antigo" route. Fix the corrupted opening sentence of the template. Nothing is activated before HG-03 (Rails credentials).
8. Cleanup: update stale comments in `app/services/scan_solo/ai_turn/context_assembler.rb:164-168` and `app/services/scan_solo/proposal/mock_provider.rb:1-7`.

## Out of scope
UI changes (the existing `scansolo/proposals` screen already has generate/approve/send/retry), follow-ups/cadence, structured "trechos", photos, OCR, automatic value/proposal number, exposing proposal status to the model, reading the old `ScanSOLO Leads` sheet.

## Survey facts (verified 2026-09-30, read-only)

### Rails (existing)
- Outbound: `ScanSolo::Proposal::MakeProvider` → `ScanSolo::Make::OutboundRequestService` (`Authorization: Bearer <scan_solo.make.secret>`, `X-Idempotency-Key`, 10s timeout, `MakeRequest` pending/sent/completed/failed, failure reasons timeout/network_error/provider_unavailable/provider_rejected). Same payload for `proposal.generate` and `proposal.send`: `account_id, opportunity_id, proposal_version_id, qualification (FieldResolver#make_qualification; only present keys; value from lead state when not faltante), requested_by_user_id, requested_at` + `correlation_id, idempotency_key, action`.
- Credentials: `Rails.application.credentials.scan_solo.make.{scenario_url, secret, inbound_signing_secret}` (`integration.rb`); missing in production → 422 `proposal_integration_not_configured`.
- Inbound: `POST /webhooks/scan_solo/make`, `X-Make-Signature` = hex HMAC-SHA256(raw body, inbound_signing_secret); schema in `callback_verifier.rb` (generate success: proposal_version_id, artifact_url, total_value, currency, valid_until; send success: proposal_version_id, sent_at, transport_message_id; failure: proposal_version_id, error_code, error_message, retryable). `valid_until`, `sent_at`, `transport_message_id` validated but not persisted.
- `ProposalVersion` enum generating/generated/approved/sent/failed; `ApproveService`, `SendService`, `RetryPolicy` (3 → dead letter + `confirm_reprocess`), `ProposalPolicy`.
- Today, on send success callback, `CallbackHandler` (`callback_handler.rb:57-73`) sends WhatsApp template `scansolo_proposal_send` via `NativeTemplateSender` (fallback content = artifact_url); `DeliveryReconciler` marks `sent` on WhatsApp delivery and `SuccessHandler` moves stage to `proposta_enviada` + enrolls post-proposal cadence. This must change to AC3 semantics.
- `CompletionService` (slice 1) sets `concluida`, stage → `qualificado`, default next_action (`orcamento`/`convite_cotacao` → `proposta`), audit; triggers nothing for proposals. `proposal_generate` AI action exists (automatic); `proposal_approve`/`proposal_send` AI actions are placeholders returning `requested`.
- `FieldResolver::MAKE_KEYS` = `empresa endereco_obra cidade_uf tipo_intervencao area profundidade prazo_desejado email nome telefone`. Catalog has `cliente_final`, `email_envio_proposta`, `emails_copia_proposta`, `link_local`.
- No proposal jobs; no sweeper for versions stuck in `generating` (generate callback only arrives after the commercial team fills the approval Form — may take days; keep as is unless SPEC decides otherwise).
- No proposal mailer; no Google code in the repo.
- `GET /api/v1/accounts/:id/scan_solo/pipeline_opportunities/:id` exposes `contact_id` at root (used by Make).

### Make (team 701134, folder scanSolo)
- Canonical: `ScanSOLO_Proposta_Entrada` (6406463, INACTIVE, hook `8ilvd55w…`): Bearer `inbound_bearer` from data store `ScanSOLO_Config` (158313: chatwoot_base_url, chatwoot_api_token, inbound_bearer, signing_secret, validade_dias, email_comercial). generate: 200 accepted → GET opportunity + contact from Chatwoot API → copy Docs template `1iXxNeqPgdJXoPiOTC8KEv2xnU7MuvfRkSOUWit_1V70` → replace placeholders → store `pv_{id}`/`doc_{docId}` in `ScanSOLO_Proposta_Map` (158314) status `aguardando_comercial` → e-mail commercial team with draft link + prefilled approval Form. No callback to Rails at this step. send: export PDF → e-mail client with attachment → callback `proposal.send` success/failure (`email_failed`, retryable) → Map `enviada`. Reads `qualification.projeto` (not sent by Rails today).
- Canonical: `Aprovacao_Gate_Processor` (6177829, ACTIVE, no auth, no error handlers): receives approval Form (doc_id, numero_proposta, titulo_servico, revisao, url_logo, prazo_total, valor_numerico, valor_extenso, nome_cliente, email_cliente, nome_empresa); if Map has `doc_{id}` → fills placeholders, PDF, callback `proposal.generate` success with total_value/BRL/valid_until → Map `aguardando_aprovacao` → e-mail commercial team with link to `/app/accounts/{id}/scansolo/proposals`. Else "fluxo antigo" legacy route.
- Gaps: e-mail modules without connection (`__IMTCONN__`) in Entrada and Gate; no idempotency check in Entrada; no generate failure callback; JSON callbacks built by string concatenation (unescaped); Gate unauthenticated.
- Legacy/parallel: `Lexus_ScanSolo_Proposta_v2` (6036802, active, broken `guid()`), `CRM_Agente_Proposta` (6019491), `Aprovacao_Finalizar_Proposta` (5497443), `Aprovacao_Confirmada` (6177833).

### Drive
- Template Docs `ScanSOLO Proposta Georadar` (`1iXxNeq…`) placeholders: NOME_EMPRESA, NOME_CONTATO, DATA_SOLICITACAO, DESCRICAO_ESCOPO, PROFUNDIDADE, VALOR_NUMERICO, VALOR_EXTENSO (+ ones replaced by Make: PROJETO_CLIENTE_FINAL, CIDADE_ESTADO, RUA_CIDADE_ESTADO, AREA_TOTAL, NÚMERO_PROPOSTA, etc.). Opening sentence corrupted ("Conforme solicitação realizada no dia vestigação geofísica…"). Scope photo and schedule remain manual.
- Approval sheet/Form `Aprovação_Orçamento`: commercial team fills value, number, revision, logo, map image, activities, schedule, deadline, value in words.

### Field mapping (old form → LeadState)
nome→nome; e-mail→email; empresa→empresa(+cnpj); telefone→telefone; logradouro→endereco_obra(+bairro); cidade/estado→cidade_uf; objetivo→tipo_intervencao; profundidade→profundidade; integração→integracao_seguranca; duração→tempo_integracao; KMZ/Maps→link_local; trechos→area/metragem (free text); site, photos → no key.

## Human gates / external dependencies
HG-03 (Rails credentials = ScanSOLO_Config values), Chatwoot API token in Make config, `atendimento.comercial@scansolo.com.br` connected in Make, WhatsApp template `scansolo_proposal_send` approved (HG-02), commercial team keeps filling the approval Form.
