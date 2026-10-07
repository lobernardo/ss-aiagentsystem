# Phases: scansolo-proposta-aprovacao-email

Gerado por /plan a partir de PLAN.md — view executável para `./ralph.sh .spec/features/scansolo-proposta-aprovacao-email/PHASES.md`.

Regras transversais (de `AGENTS.md`/`CLAUDE.md`, `docs/agents/architecture.md`, `docs/agents/domain_rules.md`):
- Controllers: gate 404 `scansolo_enabled`, Pundit (403) e validação de borda (422). Services: regras, transações, locks e auditoria (1 service por transição). Listener: só classifica e delega. Models: enums, associações, validações e predicados.
- `CallbackHandler` é o único escritor de `value`/`currency`/`artifact_url`. `StageTransitionService` (via `SuccessHandler`) é o único caminho para `proposta_enviada`.
- RNF-01: download do PDF, e-mails, aviso WhatsApp e HTTP ao Make só depois do commit (`ActiveRecord.after_all_transactions_commit` ou job). `Quote::EmailThread.post!` levanta `DeliveryInsideTransaction` dentro de transação.
- RF-10/RNF-05: 0 linhas de diff em `ai_turn/prompt_builder.rb`, `input_guardrail.rb`, `output_validator.rb`, `context_assembler.rb`, `actions/registry.rb`, `actions/proposal_actions.rb`, seeds de conhecimento, `app/services/whatsapp/`, `app/models/channel/whatsapp.rb`.
- Reusar o nativo: `ConversationReplyMailer` (`cc_emails` e anexos), `SafeFetch`, ActiveStorage, `ContactInboxWithContactBuilder`, `NativeTemplateSender`, `TemplateAvailabilityGuard`, `components-next/dialog/Dialog.vue`. 0 referências a `enterprise/`/`Captain::`.
- i18n: backend em `config/locales/en.yml` (seção `scan_solo`); frontend em `app/javascript/dashboard/i18n/locale/en/scansolo.json`. Sem strings soltas.
- Estilo: `class ScanSolo::...` compacta, 1 classe por arquivo, ≤150 colunas, header comment com RF/CT/RNF. Vue com `<script setup>`, Tailwind e `components-next/`.
- Specs Ruby e rubocop: `docker exec scansolo-phase2-test sh -c 'cd /app && bundle exec rspec <paths>'` (rubocop: `bundle exec rubocop --force-exclusion <paths>`). Depois da Phase 3: `docker exec scansolo-phase2-test sh -c 'cd /app && RAILS_ENV=test bundle exec rails db:migrate'`. Vitest: `pnpm test <paths>`. ESLint com os `.vue` explícitos. Playwright: `cd tests/playwright && npx playwright test <spec> --repeat-each=3 --retries=0 --workers=1`.
- RNF-10: um spec existente só muda de expectativa por mudança prevista no SPEC, citando o requisito. Nunca `skip`/`pending`/`xit`.
- Base de comparação: o commit `docs(spec)` deste plano (último commit só de `.spec/` antes do 1º commit de código); até lá, `29cfe766cf`.
- Phases 1–2 (UI do takeover) são independentes e podem ir a produção antes de tudo. Phases 6–10 vão juntas no mesmo deploy.
- As Phases 15, 16, 17 e 18 NÃO são executadas pelo `ralph.sh`: são de operador/humano (instância Chatwoot, Meta, Make via MCP com aprovação do desenvolvedor). Os checkboxes ficam para registro e só são marcados `[x]` com a evidência descrita. Elas substituem as OC/T36–T39 (Phases 16–18 da OC).

## Phase 1: UI — destrave do "Assumir conversa"

Antes de implementar, leia:
1. `.spec/features/scansolo-proposta-aprovacao-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-proposta-aprovacao-email/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T01 — `HandoffControlBanner`: diálogo teleportado, fechamento em erro e no takeover implícito (UI-04, UI-05, UI-06, UI-08)
      Arquivos: `app/javascript/dashboard/components-next/conversation/HandoffControlBanner.vue`, `app/javascript/dashboard/components-next/conversation/specs/HandoffControlBanner.spec.js`, `app/javascript/dashboard/i18n/locale/en/scansolo.json` (só `SCANSOLO.HANDOFF_BANNER.ERROR`)
      Mudança: trocar o `div fixed inset-0` por `<Dialog ref="reasonDialog">` (`components-next/dialog/Dialog.vue`, Teleport) com o input de motivo; Cancelar/Esc fecham sem requisição; `confirmTakeover` fecha o diálogo no sucesso e no erro (POST ou GET), com `useAlert(t('SCANSOLO.HANDOFF_BANNER.ERROR'))` no erro e `pending` falso no `finally`; `watch(controlState)` fecha o diálogo quando sai de `ai_active`; mesmo tratamento de erro em `returnToAi`; nenhuma chamada nova em mount/unmount.
      Cobre: UI-04, UI-05, UI-06, UI-08, RNF-08
      Acceptance criteria: o diálogo é renderizado fora do elemento do banner (no `body`); Esc → fechado e 0 chamadas à API; confirmar → 1 `takeover` e rótulo de estado humano; POST rejeitado → diálogo fechado, `pending` falso e alerta; `controlState` → `human_active` com o diálogo aberto → fechado; troca de conversa (novo `:key`) → 0 overlays residuais e 0 chamadas a `takeover`/`returnToAi`; `grep -n "fixed inset-0" HandoffControlBanner.vue` vazio.
      Testes: `HandoffControlBanner.spec.js` — Teleport, Esc, confirmar, erro do POST, takeover implícito, troca de conversa.
- [ ] T02 — `ConversationHeader`: botão X fecha só o painel em todos os layouts (UI-07, UI-08)
      Arquivos: `app/javascript/dashboard/components/widgets/conversation/ConversationHeader.vue`, `app/javascript/dashboard/components/widgets/conversation/specs/ConversationHeader.spec.js` (novo)
      Mudança: com `showBackButton` falso, renderizar `data-testid="conversation-close-button"` (ícone `i-lucide-x`, `aria-label` = `t('CONVERSATION.HEADER.CLOSE')`, chave existente) que faz `router.push(backButtonUrl.value)`; sem API, sem mudança de assignee/status/handoff; `ConversationBox.vue` intacto.
      Cobre: UI-07, UI-08, RNF-08
      Acceptance criteria: layout não expandido → X visível; clique → exatamente 1 `router.push` com a URL da lista e 0 requisições axios; com `showBackButton` verdadeiro o `BackButton` continua e o X não aparece; `grep -rn "ConversationHeader" enterprise` vazio.
      Testes: `ConversationHeader.spec.js` — X visível, navegação, layout expandido.

## Phase 2: E2E Playwright do takeover

Antes de implementar, leia:
1. `.spec/features/scansolo-proposta-aprovacao-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-proposta-aprovacao-email/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T03 — E2E Playwright: assumir conversa, trocar de conversa e voltar (UI-06, UI-08, RNF-11)
      Arquivos: `tests/playwright/tests/e2e/scansolo/handoff-takeover-navigation.spec.ts` (novo)
      Mudança: seed via API (admin + `api_access_token` de `tests/playwright/.env`): conta ScanSolo com inbox allowlisted publicado, 1 conversa `ai_active` e 1 2ª conversa; fluxo assumir → motivo → confirmar → clicar na 2ª conversa da lista → X → voltar à 1ª → estado humano; comparar via API `ai_control_state`, `assignee_id` e `status` antes/depois.
      Cobre: UI-06, UI-08, RNF-11
      Acceptance criteria: o spec existe e passa 3/3 com `npx playwright test tests/e2e/scansolo/handoff-takeover-navigation.spec.ts --repeat-each=3 --retries=0 --workers=1` contra a stack local; `ai_control_state`/`assignee_id`/`status` iguais antes e depois de fechar/reabrir; `pnpm --dir tests/playwright lint` sem erro.
      Testes: o próprio spec.

## Phase 3: Fundação de dados — migrações

Antes de implementar, leia:
1. `.spec/features/scansolo-proposta-aprovacao-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-proposta-aprovacao-email/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T04 — Migrações: colunas de aprovação/entrega, N versões por solicitação e `idempotency_key` único
      Arquivos: `db/migrate/20261007100001_add_approval_and_email_delivery_to_scan_solo_proposals.rb`, `db/migrate/20261007100002_allow_many_scan_solo_proposal_versions_per_quote_request.rb`, `db/migrate/20261007100003_add_unique_idempotency_key_to_scan_solo_make_requests.rb` (novos), `db/schema.rb`, `spec/db/scansolo_migrations_spec.rb`, `spec/db/scan_solo_proposal_approval_migrations_spec.rb` (novo)
      Mudança:
        • 100001: em `scan_solo_proposal_versions` `rejected_at`, `rejected_by` polimórfico, `rejection_reason` text, `approval_requested_at`, `approval_request_message_id`, `notice_message_id` (índice), `notice_failure_reason`, `artifact_sha256`; em `scan_solo_proposals` `email_conversation_id` com índice único.
        • 100002: índice de `quote_request_id` vira não único + índice único parcial `WHERE status IN (0, 2, 5)` (`index_scan_solo_proposal_versions_one_open_per_quote_request`).
        • 100003: se houver `idempotency_key` duplicada, `raise` listando as chaves antes de qualquer DDL; senão índice único.
        • `scansolo_migrations_spec.rb`: contagem 35 → 38 com comentário (RNF-07).
      Cobre: RF-07, RF-24, RF-26, RNF-02, RNF-05, RNF-07
      Acceptance criteria: `db:migrate` no container sem erro; `db/schema.rb` com as colunas e os 3 índices; 2ª versão não terminal na mesma solicitação → `RecordNotUnique`, versões `rejected` ilimitadas; fixture com chave duplicada → migração aborta com as chaves na mensagem e 0 registros alterados; contagem/status de `scan_solo_proposal_versions` iguais antes e depois; `grep -nE "remove_column|rename_column|drop_table|change_column|scan_solo_ai_agent_configs" db/migrate/20261007*` vazio.
      Testes: `spec/db/scan_solo_proposal_approval_migrations_spec.rb` e `spec/db/scansolo_migrations_spec.rb`.

## Phase 4: Modelos, política, slot do aviso, textos e exceções

Antes de implementar, leia:
1. `.spec/features/scansolo-proposta-aprovacao-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-proposta-aprovacao-email/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-proposta-aprovacao-email/openapi.yaml` — `ProposalVersionStatus`, política 403 de approve/reject/retry, `TemplateStage` (`proposta_aviso_email`)

- [ ] T05 — Modelos: status novos, associações e predicados
      Arquivos: `app/models/scan_solo/proposal_version.rb`, `app/models/scan_solo/proposal.rb`, `app/models/scan_solo/quote_request.rb`, `app/models/scan_solo/pipeline_opportunity.rb`, `spec/models/scan_solo/proposal_version_spec.rb`, `spec/models/scan_solo/quote_request_spec.rb`, `spec/models/scan_solo/pipeline_opportunity_spec.rb`
      Mudança: enum `+ awaiting_approval: 5, rejected: 6`; `NON_TERMINAL_STATUSES`; `belongs_to :rejected_by` (polimórfico), `:approval_request_message`, `:notice_message`; `QuoteRequest has_many :proposal_versions` + `generation_open?` (sem versões ou só `rejected`); `Proposal belongs_to :email_conversation`; `PipelineOpportunity#lead_email_valid?`.
      Cobre: RF-06, RF-07, RF-08, RF-26, CT-01
      Acceptance criteria: `ProposalVersion.statuses` com 0–4 inalterados e 5/6 novos; `generation_open?` verdadeiro sem versões e só com `rejected`, falso com `failed`/`sent`/`awaiting_approval`; `lead_email_valid?` falso para nil e `"x@"`, verdadeiro para e-mail válido; nenhum uso restante de `quote_request.proposal_version` (`grep -rn "\.proposal_version\b" app` sem esse uso).
      Testes: os 3 specs de modelo.
- [ ] T06 — `ProposalPolicy`: administrador ou `commercial_user_id` publicado
      Arquivos: `app/policies/scan_solo/proposal_policy.rb`, `spec/policies/scan_solo/proposal_policy_spec.rb`
      Mudança: `approve?`, `reject?` (novo) e `retry?` = `administrator? || commercial_user?` (`AiAgentConfig.published_for(account)&.commercial_user_id == user.id`); `send?` inalterado.
      Cobre: RF-04, RF-05, RF-15, CT-02, CT-03, HG-F
      Acceptance criteria: admin → permitido; `agent` igual ao `commercial_user_id` publicado → permitido; outro `agent` → negado; `commercial_user_id` só no rascunho → negado.
      Testes: `proposal_policy_spec.rb`.
- [ ] T07 — Slot de template `proposta_aviso_email` (CT-07)
      Arquivos: `app/models/scan_solo/template_mapping.rb`, `spec/models/scan_solo/template_mapping_spec.rb`, `spec/requests/api/v1/accounts/scan_solo/cadence_templates_spec.rb`, `spec/services/scan_solo/executions_feed_query_spec.rb`
      Mudança: `SINGLE_TEMPLATES` + `'proposta_aviso_email' => 'scansolo_proposta_aviso_email'`; `proposta_enviada` inalterado.
      Cobre: CT-07, HG-E
      Acceptance criteria: mapeamento com `stage: 'proposta_aviso_email', step: nil` válido; `GET`/`PUT cadence_templates` aceitam o slot; `SINGLE_TEMPLATES['proposta_enviada'] == 'scansolo_proposal_send'`; a linha nova no `executions_feed_query_spec` cita CT-07.
      Testes: os 3 specs listados.
- [ ] T08 — Textos backend e exceções de domínio
      Arquivos: `config/locales/en.yml`, `lib/custom_exceptions/scan_solo.rb`
      Mudança: chaves `scan_solo.proposal.approval_request.*` (CT-05) e `scan_solo.proposal.lead_email.*` (CT-06, sem link do documento); exceções `ProposalActionRejected` e `LeadEmailRejected` com `code`, no padrão de `QuoteRequestResendRejected`.
      Cobre: CT-02, CT-03, CT-04, CT-05, CT-06, CT-09, RNF-08
      Acceptance criteria: `I18n.t` das chaves novas sem `translation missing`; as 2 exceções expõem `code`; `spec/lib/scansolo_branding_spec.rb` verde.
      Testes: `docker exec scansolo-phase2-test sh -c 'cd /app && bundle exec rspec spec/lib/scansolo_branding_spec.rb'`.

## Phase 5: Robustez e infraestrutura de e-mail

Antes de implementar, leia:
1. `.spec/features/scansolo-proposta-aprovacao-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-proposta-aprovacao-email/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-proposta-aprovacao-email/asyncapi.yaml` — `negotiationRequested` (RF-23), `ProposalApprovalRequestEmailPayload` e `ProposalLeadEmailPayload` (CT-05/CT-06)

- [ ] T09 — `OutboundRequestService`: chave de idempotência única sem 2ª requisição HTTP (RF-24)
      Arquivos: `app/services/scan_solo/make/outbound_request_service.rb`, `spec/services/scan_solo/make/outbound_request_service_spec.rb`
      Mudança: `rescue ActiveRecord::RecordNotUnique` no `create!` → devolve o `MakeRequest` existente pela `idempotency_key`, sem `deliver!`.
      Cobre: RF-24, RNF-02
      Acceptance criteria: 2 chamadas com a mesma chave → 1 `MakeRequest` e 1 requisição WebMock.
      Testes: `outbound_request_service_spec.rb`.
- [ ] T10 — `MakeProvider`: auditoria `proposal.generation_failed` na falha de transporte (RF-20)
      Arquivos: `app/services/scan_solo/proposal/make_provider.rb`, `spec/services/scan_solo/proposal/make_provider_spec.rb`
      Mudança: no `rescue DeliveryError` de `proposal.generate`, além de `failed` + motivo, 1 `AuditEvent` `proposal.generation_failed` com `reason`, `generate_correlation_id` e o correlation da solicitação.
      Cobre: RF-20, RNF-06
      Acceptance criteria: timeout WebMock → versão `failed`/`timeout` e 1 auditoria com os 2 correlation ids; HTTP 500 → `provider_unavailable` e 1 auditoria.
      Testes: `make_provider_spec.rb`.
- [ ] T11 — `Quote::RequestService`: retry do job reenvia o e-mail de solicitação 1 vez (RF-22)
      Arquivos: `app/services/scan_solo/quote/request_service.rb`, `spec/services/scan_solo/quote/request_service_spec.rb`
      Mudança: `open_request!`, sob o lock da oportunidade, devolve a solicitação existente quando `request_message_id` é nulo; `deliver!` fora da transação.
      Cobre: RF-22, RNF-01
      Acceptance criteria: 1ª execução com `EmailThread.post!` levantando → solicitação sem `request_message_id`; 2ª → 1 mensagem, `request_message_id` gravado, 1 solicitação e 1 conversa; 3ª → 0 mensagens novas.
      Testes: `request_service_spec.rb`.
- [ ] T12 — `Notifications::Publisher`: ≤ 1 publicação por `correlation_id` (RF-23)
      Arquivos: `app/services/scan_solo/notifications/publisher.rb`, `spec/services/scan_solo/notifications/publisher_spec.rb`
      Mudança: reivindicação sob `opportunity.with_lock` por `AuditEvent` `negotiation.notification_claimed` com o `correlation_id`; já reivindicado → não publica; publicação fora da transação.
      Cobre: RF-23, RNF-02
      Acceptance criteria: 2 `Publisher.call` com o mesmo `correlation_id` → 1 e-mail de negociação; `correlation_id` diferente → 2.
      Testes: `publisher_spec.rb`.
- [ ] T13 — `ReplyInterruptionService`: em `proposta_enviada` cancela todas as tentativas (RF-18)
      Arquivos: `app/services/scan_solo/cadence/reply_interruption_service.rb`, `spec/services/scan_solo/cadence/reply_interruption_service_spec.rb`
      Mudança: `opportunity.proposta_enviada?` → cancela todas as tentativas `scheduled` de cada matrícula ativa criada antes da mensagem, 1 auditoria `cadence.attempt_interrupted_by_reply` por tentativa; outras etapas mantêm ≤ 1 por ciclo; assinatura inalterada.
      Cobre: RF-18, RNF-06
      Acceptance criteria: `proposta_enviada` + 3 `scheduled` → 3 `cancelled` e 3 auditorias; tentativa `sent` inalterada; `em_contato` + 3 `scheduled` → 1 `cancelled`; 2ª mensagem → 0 cancelamentos novos.
      Testes: `reply_interruption_service_spec.rb`.
- [ ] T14 — `Quote::EmailThread`: CC, anexos e atributos de origem
      Arquivos: `app/services/scan_solo/quote/email_thread.rb`, `spec/services/scan_solo/quote/email_thread_spec.rb`
      Mudança: `post!(…, cc: [], attachments: [], additional_attributes: {})` grava `content_attributes.cc_emails`, cria os anexos (blobs) na mesma criação da mensagem e grava `additional_attributes`; `open!` inalterado.
      Cobre: CT-05, CT-06, RNF-01
      Acceptance criteria: 1 mensagem com 1 anexo (mesmo checksum do blob), `cc_emails` e `additional_attributes`; com `perform_enqueued_jobs` + ActionMailer `:test` → 1 e-mail com cabeçalho `Cc` e 1 anexo `application/pdf`; dentro de transação → `DeliveryInsideTransaction`; chamadas antigas sem os kwargs inalteradas.
      Testes: `email_thread_spec.rb`.
- [ ] T15 — `Quote::EmailComposer`: pedido de aprovação (CT-05) e proposta ao lead (CT-06)
      Arquivos: `app/services/scan_solo/quote/email_composer.rb`, `spec/services/scan_solo/quote/email_composer_spec.rb`
      Mudança: `approval_request(proposal_version:)` com número, versão, valor/moeda, lead, aviso "falta e-mail do lead" quando `!lead_email_valid?`, link `<FRONTEND_URL>/app/accounts/<id>/scansolo/proposals` e a frase "aprovação só pela tela"; `lead_proposal(proposal_version:)` com assunto contendo o número e corpo sem link.
      Cobre: CT-05, CT-06, RF-08, RNF-08, RNF-09
      Acceptance criteria: texto e HTML do pedido contêm número, versão, valor e o link; contato sem e-mail → aviso presente; `lead_proposal` com 0 URLs no corpo e o número no assunto; valores escapados no HTML.
      Testes: `email_composer_spec.rb`.

## Phase 6: Callback em `awaiting_approval` e pedido de aprovação

Antes de implementar, leia:
1. `.spec/features/scansolo-proposta-aprovacao-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-proposta-aprovacao-email/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-proposta-aprovacao-email/asyncapi.yaml` — `makeIntegrationCallback` (CT-08: `total_value`, `artifact_sha256`, `template_version`) e `proposalApprovalRequestEmail` (CT-05)

- [ ] T16 — Callback → `awaiting_approval`, PDF armazenado e pedido de aprovação (RF-01, RF-02, RF-20, RF-25)
      Arquivos: `app/services/scan_solo/proposal/callback_handler.rb`, `app/services/scan_solo/proposal/approval_request_service.rb` (novo), `app/jobs/scan_solo/proposal_approval_request_job.rb` (novo), `spec/services/scan_solo/proposal/callback_handler_spec.rb`, `spec/services/scan_solo/proposal/approval_request_service_spec.rb` (novo), `spec/jobs/scan_solo/proposal_approval_request_job_spec.rb` (novo), `spec/services/scan_solo/proposal/mock_provider_spec.rb`
      Mudança:
        • `CallbackHandler.apply_generate_result!(…, artifact_sha256: nil, template_version: nil)`: sucesso → `awaiting_approval` + `artifact_sha256`, auditoria `proposal.generated` com `template_version`, após o commit `ProposalApprovalRequestJob` (no lugar do `ProposalDeliveryJob`); falha → + 1 `proposal.generation_failed`.
        • `ApprovalRequestService.call(proposal_version:, redownload: false)`: baixa o PDF (código movido de `DeliveryService#store_document`, `SafeFetch` só `application/pdf`), compara `artifact_sha256`, reivindica sob lock por `approval_requested_at`, posta o CT-05 na `email_conversation` da solicitação para o `quote_recipient_email` publicado com o PDF anexo, grava `approval_request_message` e 1 `proposal.approval_requested`. Falhas → `failed` com `artifact_download_failed`/`artifact_checksum_mismatch` + 1 `proposal.delivery_failed`, 0 e-mails.
      Cobre: RF-01, RF-02, RF-20, RF-25, CT-05, RNF-01, RNF-02, RNF-03, RNF-06
      Acceptance criteria: callback de sucesso → `awaiting_approval`, 1 job de pedido de aprovação, 0 `ProposalDeliveryJob`, 0 mensagens na conversa WhatsApp, etapa inalterada, 0 `PipelineStageEvent` e 0 matrículas; o job → 1 blob `application/pdf`, 1 mensagem `outgoing` na `email_conversation` da solicitação com 1 anexo `<número>.pdf`, `to_emails` = [`quote_recipient_email`] e o link no corpo; 2ª execução → 1 mensagem; HTTP 500 → `failed`/`artifact_download_failed`, 1 auditoria e 0 e-mails; checksum divergente → `failed`/`artifact_checksum_mismatch` e 0 e-mails; falha de callback → 1 `proposal.generation_failed`; envio dentro de transação levanta.
      Testes: `callback_handler_spec.rb` (expectativas de `OC/RF-29` substituídas citando RF-01), `approval_request_service_spec.rb`, `proposal_approval_request_job_spec.rb`, `mock_provider_spec.rb`.
- [ ] T17 — `CallbackVerifier`/`CallbackApplicationService`: `total_value` conferido e rejeições auditadas (RF-19, RF-20, RF-25, CT-08)
      Arquivos: `app/services/scan_solo/make/callback_verifier.rb`, `app/services/scan_solo/make/callback_application_service.rb`, `spec/services/scan_solo/make/callback_application_service_spec.rb`, `spec/requests/webhooks/scan_solo/make_spec.rb`
      Mudança: schema aceita `artifact_sha256` (hex 64) e `template_version` opcionais; `total_value` de `proposal.generate` + `success` comparado em centavos com `commercial.total_value` da solicitação → `total_value_mismatch`; todo `reject!` com assinatura válida grava `MakeCallback` + 1 `make.callback_rejected`; `apply_generate!` repassa os 2 campos ao `CallbackHandler`.
      Cobre: RF-19, RF-20, RF-25, CT-08, RNF-06
      Acceptance criteria: pedido 12500.00 e callback 12000.00 → 422, versão `generating`, `value` nulo, 1 `MakeCallback` `total_value_mismatch` e 1 auditoria com os 2 valores; 12500.0 → 200 e `awaiting_approval`; schema inválido → 422 e 1 `make.callback_rejected`; assinatura inválida → 401, 0 `AuditEvent` e 0 `MakeCallback`; callback com e sem `artifact_sha256`/`template_version` → 200.
      Testes: `make_spec.rb`, `callback_application_service_spec.rb`.

## Phase 7: Aprovar/Rejeitar, entrega por e-mail e aviso

Antes de implementar, leia:
1. `.spec/features/scansolo-proposta-aprovacao-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-proposta-aprovacao-email/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-proposta-aprovacao-email/asyncapi.yaml` — `proposalLeadEmail` (CT-06) e `proposalLeadNotice` (CT-07)
4. `.spec/features/scansolo-proposta-aprovacao-email/openapi.yaml` — `approveProposal`/`rejectProposal` (códigos 422)

- [ ] T18 — Aprovação auditada e rejeição com motivo (RF-04, RF-05)
      Arquivos: `app/services/scan_solo/proposal/approve_service.rb`, `app/services/scan_solo/proposal/reject_service.rb` (novo), `spec/services/scan_solo/proposal/approve_service_spec.rb`, `spec/services/scan_solo/proposal/reject_service_spec.rb` (novo)
      Mudança: `ApproveService` sob lock: `approved`/`sent` → idempotente; não vigente → `not_current_version`; ≠ `awaiting_approval` → `not_awaiting_approval`; senão `approved` + `approved_at`/`approved_by` + 1 `proposal.approved` + `ProposalDeliveryJob` após o commit; ignora `require_proposal_approval`. `RejectService` com lock da solicitação e da versão: `rejected` + `rejected_at`/`rejected_by`/`rejection_reason`, solicitação `awaiting_reply`, 1 `proposal.rejected`, 0 entregas.
      Cobre: RF-04, RF-05, RF-06, RNF-02, RNF-06
      Acceptance criteria: 1ª aprovação → `approved`, 1 auditoria, 1 job; 2ª → 0 auditorias e 0 jobs novos; 2 threads concorrentes → 1 auditoria e 1 job; `require_proposal_approval = false` publicado não muda nada; rejeição → `rejected` com motivo, solicitação `awaiting_reply`, 1 auditoria e 0 jobs de entrega; rejeitar `approved` → `ProposalActionRejected('not_awaiting_approval')`.
      Testes: `approve_service_spec.rb` (expectativas de `OC/RF-78` substituídas citando RF-04), `reject_service_spec.rb`.
- [ ] T19 — Entrega por e-mail ao lead com CC e PDF (RF-08, RF-11, RF-12, RF-14)
      Arquivos: `app/services/scan_solo/proposal/delivery_service.rb`, `app/jobs/scan_solo/proposal_delivery_job.rb`, `spec/services/scan_solo/proposal/delivery_service_spec.rb`
      Mudança: reescrever `DeliveryService`: claim sob lock (`approved` sem `sent_message_id`, ou `redeliver` de `failed` com `approved_at`); sem e-mail válido → `lead_email_missing`; sem documento → `email_delivery_failed`; conversa de proposta 1 por oportunidade (`proposal.email_conversation`, marcador `proposal_delivery`, criada sob lock do `Proposal`); `post!` com To = `contact.email`, CC = `quote_recipient_email` publicado, PDF anexo, `scansolo_origin: proposal_email` e `scansolo_proposal_version_id`; `sent_message` = e-mail; exceção → `email_delivery_failed`; toda falha → `failed` + 1 `proposal.delivery_failed`, etapa intacta; 0 `MakeRequest`; `store_document` removido.
      Cobre: RF-08, RF-11, RF-12, RF-14, RF-17, CT-06, RNF-01, RNF-02
      Acceptance criteria: após aprovação → 1 mensagem `outgoing` no inbox de orçamento com `to_emails` = [`contact.email`], `cc_emails` = [`quote_recipient_email`] e 1 anexo com o checksum do blob da versão; e-mail entregue (ActionMailer `:test`) com `Cc` = `comercial@scansolo.com.br`; 0 mensagens WhatsApp e 0 `MakeRequest`; 2 execuções → 1 e-mail; versão 2 após rejeição da 1 → mesma conversa de proposta (1 por oportunidade); contato sem e-mail → `failed`/`lead_email_missing` e etapa inalterada; envio fora de transação.
      Testes: `delivery_service_spec.rb` (expectativas de `OC/RF-29`/CT-10 substituídas citando RF-11).
- [ ] T20 — Aviso WhatsApp sem PDF depois de `sent` (RF-11, RF-12, RF-14, CT-07)
      Arquivos: `app/services/scan_solo/proposal/lead_notice_service.rb` (novo), `app/services/scan_solo/proposal/success_handler.rb`, `spec/services/scan_solo/proposal/lead_notice_service_spec.rb` (novo), `spec/services/scan_solo/proposal/success_handler_spec.rb`
      Mudança: `LeadNoticeService` sob lock: só `sent` e só se `notice_message` nulo ou `failed`; slot `proposta_aviso_email` + guard na conversa WhatsApp; bloqueado → `notice_failure_reason` + 1 `proposal.lead_notice_failed`; senão `NativeTemplateSender` com `origin: 'proposal_notice'`, sem documento. `SuccessHandler` chama o aviso e depois o `FollowUpService` no `after_all_transactions_commit`.
      Cobre: RF-11, RF-12, RF-13, RF-14, CT-07, RNF-01, RNF-02
      Acceptance criteria: versão `sent` → 1 mensagem WhatsApp com `scansolo_origin: proposal_notice` e sem `media_url` em `processed_params`; 2ª chamada → continua 1; guard `template_missing` → 1 `proposal.lead_notice_failed` e versão `sent`; versão `approved` → 0 avisos; `SuccessHandler` → 1 aviso e 1 acompanhamento depois do commit.
      Testes: `lead_notice_service_spec.rb`, `success_handler_spec.rb`.

## Phase 8: Reconciliação, reenvio e `/send` legado

Antes de implementar, leia:
1. `.spec/features/scansolo-proposta-aprovacao-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-proposta-aprovacao-email/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-proposta-aprovacao-email/asyncapi.yaml` — `nativeMessageUpdated` (origens `proposal_email`/`proposal_notice`)
4. `.spec/features/scansolo-proposta-aprovacao-email/openapi.yaml` — `retryProposal` (casos a/b/c) e `sendProposal` (CT-04)

- [ ] T21 — Reconciliação do e-mail: `sent` só com `source_id`, falhas e aviso (RF-13, RF-14)
      Arquivos: `app/services/scan_solo/messaging/delivery_reconciler.rb`, `app/services/scan_solo/conversation_listener.rb`, `spec/services/scan_solo/messaging/delivery_reconciler_spec.rb`, `spec/services/scan_solo/conversation_listener_spec.rb`
      Mudança: `TEMPLATE_ORIGINS` + `proposal_email`, `proposal_notice`; `outcome` exige `source_id` também para `Channel::Email`; `reconcile_version` por `sent_message_id` (aceito → `sent` + `proposal.sent` + `SuccessHandler`; `failed` antes/depois de `sent` como hoje); novo: versão por `notice_message_id` com `failed` → `notice_failure_reason` + 1 `proposal.lead_notice_failed`, status inalterado.
      Cobre: RF-12, RF-13, RF-14, RNF-02, RNF-06
      Acceptance criteria: e-mail sem `source_id` → versão `approved`, etapa inalterada e 0 avisos; `source_id` → `sent`, `proposta_enviada`, 1 `PipelineStageEvent`, 1 matrícula `proposta_enviada` e 1 aviso após o commit; 2 reconciliações → 1 aviso; e-mail `failed` → versão `failed` e 0 avisos; `failed` após `sent` → 1 `proposal.delivery_failed_after_sent` e etapa mantida; aviso `failed` → 1 `proposal.lead_notice_failed` e versão `sent`; listener chama o reconciliador para `proposal_email`.
      Testes: `delivery_reconciler_spec.rb` (expectativas de `OC/RF-30` substituídas citando RF-13), `conversation_listener_spec.rb`.
- [ ] T22 — `RetryPolicy`: reenvio na mesma versão por causa (RF-15)
      Arquivos: `app/services/scan_solo/proposal/retry_policy.rb`, `spec/services/scan_solo/proposal/retry_policy_spec.rb`
      Mudança: `retryable?` = `failed?` e (a) `approved_at` presente, (c) motivo em `artifact_download_failed`/`artifact_checksum_mismatch` ou (b) motivo seguro atual; (a) audita `operation: 'email_delivery'` e chama `DeliveryService.call(redeliver: true)`; (c) audita `operation: 'artifact_download'` e chama `ApprovalRequestService.call(redownload: true)`; (b) caminho atual com dead letter; remove `delivery_stage?`/`retry_delivery!` do WhatsApp.
      Cobre: RF-15, RF-07, RNF-02
      Acceptance criteria: (a) com aviso aceito → 1 e-mail novo com o mesmo blob, 0 avisos, 0 downloads e 0 `MakeRequest`; (a) sem aviso aceito → 0 avisos até o `source_id` e 1 depois; (b) timeout → `generating`, mesmo `id`, 1 `MakeRequest`; (c) → 1 download WebMock, `awaiting_approval`, 1 CT-05 e 0 `MakeRequest`; nenhum caso cria versão nova.
      Testes: `retry_policy_spec.rb` (expectativas de CT-10 da OC substituídas citando RF-15).
- [ ] T23 — `/send` legado sem `proposal.send` (RF-21, CT-04)
      Arquivos: `app/services/scan_solo/proposal/send_service.rb`, `spec/services/scan_solo/proposal/send_service_spec.rb`
      Mudança: não vigente → `not_current_version`; `sent` → `already_sent`; ≠ `approved` → `approval_required`; `approved` → `DeliveryService.call` (idempotente); sem `provider.request_send` nem `send_correlation_id`.
      Cobre: RF-21, CT-04
      Acceptance criteria: `sent` → `already_sent` e 0 `MakeRequest`; `awaiting_approval` → `approval_required`; `approved` com entrega feita → 0 e-mails novos; `grep -n "request_send" app/services/scan_solo/proposal/send_service.rb` vazio.
      Testes: `send_service_spec.rb` (expectativas antigas de `proposal.send` substituídas citando RF-21).

## Phase 9: Nova versão após rejeição e resposta do lead

Antes de implementar, leia:
1. `.spec/features/scansolo-proposta-aprovacao-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-proposta-aprovacao-email/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-proposta-aprovacao-email/asyncapi.yaml` — `proposalLeadEmailReply` (RF-16) e `proposalApprovalRequestEmail` (respostas na thread)
4. `.spec/features/scansolo-proposta-aprovacao-email/openapi.yaml` — `generateProposal` (RF-07)

- [ ] T24 — Correlação da resposta do lead por e-mail (RF-16)
      Arquivos: `app/services/scan_solo/proposal/lead_email_reply_service.rb` (novo), `spec/services/scan_solo/proposal/lead_email_reply_service_spec.rb` (novo)
      Mudança: acha o `Proposal` por `email_conversation_id`; remetente (`message.sender.email`, sem caixa) ≠ e-mail do contato → sem efeito; igual → sob lock da oportunidade e só se ainda não houver auditoria para o `message_id`: `record_customer_interaction!`, `ReplyInterruptionService.call` e 1 `proposal.lead_email_reply` com o correlation da solicitação.
      Cobre: RF-16, RF-18, RNF-06
      Acceptance criteria: reply do lead → 0 `QuoteReply`, 0 `PipelineOpportunity` novas, 0 `AiTurn`, `last_customer_interaction_at` = `message.created_at` e 1 auditoria; reprocessar → continua 1; reply de `comercial@` → interação inalterada, 0 cancelamentos e 0 auditorias; em `proposta_enviada` com 3 `scheduled` → 3 `cancelled`.
      Testes: `lead_email_reply_service_spec.rb`.
- [ ] T25 — Nova versão após rejeição e roteamento das 3 threads (RF-03, RF-06, RF-07, RF-17)
      Arquivos: `app/services/scan_solo/proposal/generate_service.rb`, `app/services/scan_solo/quote/reply_processor.rb`, `spec/services/scan_solo/proposal/generate_service_spec.rb`, `spec/services/scan_solo/quote/reply_processor_spec.rb`, `spec/requests/api/v1/accounts/scan_solo/proposals_spec.rb` (caso `generate`)
      Mudança: `GenerateService` exige `replied? && generation_open?`; `ReplyProcessor.call` roteia (1) solicitação → `apply`, (2) `scansolo_thread == 'proposal_delivery'` → `LeadEmailReplyService`, (3) negociação → ignora, (4) `unmatched`; `request_generation!` só com `generation_open?`; o resto de `apply` intacto (`late_reply` com solicitação `replied`).
      Cobre: RF-03, RF-06, RF-07, RF-17, RNF-02
      Acceptance criteria: `awaiting_approval` + "Aprovado, pode enviar" → `awaiting_approval`, `approved_at` nulo, 1 `late_reply`, 0 versões, 0 e-mails ao lead e 0 WhatsApp; idem com bloco válido; `failed`/`artifact_download_failed` + bloco válido → 1 `late_reply`, 0 versões e 0 `MakeRequest`; versão 1 `rejected` + bloco válido `9.000,00` → versão 2 `generating`, `is_current` só nela, mesma `quote_request_id`, 1 `MakeRequest` com `commercial.total_value` 9000.0 e versão 1 legível; bloco inválido → 0 versões e 1 correção; 2 replies válidos concorrentes → 1 versão; reply na thread de proposta → `LeadEmailReplyService`; na de negociação → ignorado; `POST generate` com versão `awaiting_approval` → 422 e 0 versões.
      Testes: `generate_service_spec.rb`, `reply_processor_spec.rb`, `proposals_spec.rb`.

## Phase 10: API de Propostas e e-mail do lead

Antes de implementar, leia:
1. `.spec/features/scansolo-proposta-aprovacao-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-proposta-aprovacao-email/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-proposta-aprovacao-email/openapi.yaml` — approve/reject/send/retry, `ProposalVersion`, `Proposal`, `PipelineOpportunity`, PATCH `email`

- [ ] T26 — API de Propostas: approve, reject, send, retry e leitura (CT-01..CT-04)
      Arquivos: `config/routes.rb`, `app/controllers/api/v1/accounts/scan_solo/proposals_controller.rb`, `app/views/api/v1/accounts/scan_solo/proposals/_proposal.json.jbuilder`, `app/views/api/v1/accounts/scan_solo/proposals/_proposal_version.json.jbuilder`, `app/views/api/v1/accounts/scan_solo/proposals/reject.json.jbuilder` (novo), `spec/requests/api/v1/accounts/scan_solo/proposals_spec.rb`, `spec/policies/scan_solo/coverage_audit_spec.rb`
      Mudança: rota `post :reject`; `rescue_from ProposalActionRejected` → `422 { error: code }`; approve com `lead_email_missing` na borda para versão `awaiting_approval`; reject com `reason_required` na borda; send via `SendService`; retry com a política nova; preload de `approved_by`, `rejected_by`, `sent_message`, `notice_message`, documento, contato e solicitação; `_proposal_version` + `approved_by`, `rejected_at`, `rejected_by`, `rejection_reason`, `delivery { email_status, notice_status }`; `_proposal` + `lead_email_present`; campos atuais intactos.
      Cobre: CT-01, CT-02, CT-03, CT-04, RF-04, RF-05, RF-08, RF-15, RF-21, RF-26, RNF-02
      Acceptance criteria: approve 1º → 200, `approved`, `approved_by_id`, 1 auditoria e 1 job; 2º → 200 e mesmas contagens; 2 POSTs concorrentes → 1 auditoria; `commercial_user_id` publicado com papel `agent` → 200; outro `agent` → 403 e 0 auditorias; contato sem e-mail → 422 `lead_email_missing` e versão `awaiting_approval`; reject → 200 e solicitação `awaiting_reply`; motivo `"  "` → 422 `reason_required`; reject em `approved` → 422 `not_awaiting_approval`; send → 422 `already_sent`/`approval_required` e 0 `MakeRequest`; retry por outro `agent` → 403; `GET` com versões legadas `generated`/`approved`/`sent` → 0 erros, campos novos presentes; `scansolo_enabled` desligado → 404; coverage audit inclui `reject`.
      Testes: `proposals_spec.rb`, `coverage_audit_spec.rb`.
- [ ] T27 — E-mail do lead editável e `lead_email` na leitura (RF-09, CT-09, CT-01)
      Arquivos: `app/controllers/api/v1/accounts/scan_solo/pipeline_opportunities_controller.rb`, `app/services/scan_solo/pipeline/lead_email_service.rb` (novo), `app/views/api/v1/accounts/scan_solo/pipeline_opportunities/_pipeline_opportunity.json.jbuilder`, `app/views/api/v1/accounts/scan_solo/pipeline_opportunities/_detail.json.jbuilder`, `spec/requests/api/v1/accounts/scan_solo/pipeline_opportunities_spec.rb`, `spec/services/scan_solo/pipeline/lead_email_service_spec.rb` (novo)
      Mudança: `update_params` + `email`; formato inválido/vazio → 422 `invalid_email` na borda; `LeadEmailService` grava `Contact.email` e converte a falha de unicidade nativa em `contact_conflict` (422); `_pipeline_opportunity` + `lead_email`; `_detail` `proposal.rejection_reason`.
      Cobre: RF-09, CT-09, CT-01, UI-02
      Acceptance criteria: PATCH `{ email: "lead@empresa.com.br" }` → 200 e `contact.email` gravado; `"x@"` → 422 `invalid_email`; e-mail de outro contato → 422 `contact_conflict` e contato inalterado; após o PATCH, o approve que dava 422 `lead_email_missing` dá 200; index/show com `lead_email`.
      Testes: `pipeline_opportunities_spec.rb`, `lead_email_service_spec.rb`.

## Phase 11: Frontend base — textos, API, stores e rótulos

Antes de implementar, leia:
1. `.spec/features/scansolo-proposta-aprovacao-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-proposta-aprovacao-email/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-proposta-aprovacao-email/openapi.yaml` — payloads e códigos de erro consumidos pela UI

- [ ] T28 — Frontend base: textos, API, stores, rótulos e papel comercial
      Arquivos: `app/javascript/dashboard/i18n/locale/en/scansolo.json`, `app/javascript/dashboard/api/scansoloProposals.js`, `app/javascript/dashboard/api/scansoloPipelineOpportunities.js`, `app/javascript/dashboard/store/scansolo/proposals.js`, `app/javascript/dashboard/store/scansolo/pipelineOpportunities.js`, `app/javascript/dashboard/routes/dashboard/scansolo/scansoloLabels.js`, `app/javascript/dashboard/routes/dashboard/scansolo/composables/useScanSoloRole.js`, `app/javascript/dashboard/store/scansolo/specs/proposals.spec.js` (novo), `app/javascript/dashboard/store/scansolo/specs/pipelineOpportunities.spec.js`
      Mudança: API `reject` e `updateLeadEmail` (PATCH `{ email }`); stores `rejectProposal` e `updateLeadEmail`; rótulos de status (`awaiting_approval`, `rejected`), status comercial, motivos (`lead_email_missing`, `email_delivery_failed`, `artifact_download_failed`, `artifact_checksum_mismatch`), erros de ação e de e-mail, slot `proposta_aviso_email`; `useScanSoloRole` com `isCommercialUser`/`canApproveProposals`; textos i18n novos.
      Cobre: UI-01, UI-02, UI-03, CT-02, CT-03, CT-09, RNF-08
      Acceptance criteria: `rejectProposal` chama `POST .../reject` com `{ proposal_version_id, reason }` e atualiza a versão no store; `updateLeadEmail` chama `PATCH` com `{ email }`; todo valor novo de status/motivo/erro tem chave i18n existente; `i18nCompleteness.spec.js` verde.
      Testes: `proposals.spec.js`, `pipelineOpportunities.spec.js`, `app/javascript/dashboard/routes/dashboard/scansolo/specs/i18nCompleteness.spec.js`.

## Phase 12: Frontend — telas

Antes de implementar, leia:
1. `.spec/features/scansolo-proposta-aprovacao-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-proposta-aprovacao-email/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-proposta-aprovacao-email/openapi.yaml` — `ProposalVersion.delivery`, `Proposal.lead_email_present`, `PipelineOpportunity.lead_email`

- [ ] T29 — Tela de Propostas: Aprovar e Rejeitar (UI-01)
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/proposals/Proposals.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/proposals/specs/Proposals.spec.js`
      Mudança: versão vigente `awaiting_approval` + usuário autorizado (admin ou comercial publicado) → "Aprovar" e "Rejeitar"; "Aprovar" desabilitado com aviso e link para a tela do lead sem e-mail, e enquanto `documentUrl` for nulo; "Rejeitar" abre `Dialog.vue` com motivo obrigatório; status "Aguardando aprovação"/"Aprovada"/"Rejeitada" + motivo/"Enviada", falha com motivo e `delivery`; erros 422 por código via `useAlert`; "Enviar" e toggle ocultos; "Reenviar" para admin ou comercial.
      Cobre: UI-01, RF-04, RF-05, RF-08, RF-15
      Acceptance criteria: fixture `awaiting_approval` → Aprovar e Rejeitar visíveis; Aprovar → 1 POST approve; Rejeitar + motivo → 1 POST reject; motivo vazio → confirmar desabilitado e 0 requisições; sem e-mail → Aprovar desabilitado e aviso visível; `sent` → 0 botões de ação; 0 botões "Enviar"; `agent` não comercial → 0 Aprovar/Rejeitar; os casos existentes de versão `generated` sem aprovar continuam verdes.
      Testes: `Proposals.spec.js` (mudança de expectativa só para `awaiting_approval`, citando UI-01).
- [ ] T30 — Tela do lead: e-mail editável e status da proposta (UI-02)
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/OpportunityDetail.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/specs/OpportunityDetail.spec.js`
      Mudança: bloco "E-mail do lead" com valor, editar/salvar (`updateLeadEmail`), aviso quando vazio e erro 422 por código; status da proposta com "Aguardando aprovação" e "Rejeitada" + `rejectionReason`.
      Cobre: UI-02, RF-08, RF-09
      Acceptance criteria: fixture sem e-mail → aviso visível; salvar → 1 PATCH e aviso oculto no sucesso; 422 `invalid_email` → mensagem i18n; versão `rejected` → motivo visível.
      Testes: `OpportunityDetail.spec.js`.
- [ ] T31 — Kanban e Templates: rótulos novos (UI-03, CT-07)
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/specs/KanbanBoard.spec.js`, `app/javascript/dashboard/routes/dashboard/scansolo/followups/specs/TemplatesPanel.spec.js`
      Mudança: casos de spec para `proposalStatus` `awaiting_approval`/`rejected` e para a linha do slot `proposta_aviso_email` (componentes só mudam se dependerem de lista fixa).
      Cobre: UI-03, CT-07
      Acceptance criteria: card com `awaiting_approval` → "Aguardando aprovação"; com `rejected` → "Proposta rejeitada"; Templates → linha `proposta_aviso_email` com o rótulo do slot.
      Testes: `KanbanBoard.spec.js`, `TemplatesPanel.spec.js`.

## Phase 13: Provas ponta a ponta e documentação

Antes de implementar, leia:
1. `.spec/features/scansolo-proposta-aprovacao-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-proposta-aprovacao-email/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-proposta-aprovacao-email/openapi.yaml` e `.spec/features/scansolo-proposta-aprovacao-email/asyncapi.yaml` — contratos a documentar

- [ ] T32 — Provas ponta a ponta e RNF transversais
      Arquivos: `spec/integration/scan_solo/proposta_aprovacao_email_spec.rb` (novo), `spec/integration/scan_solo/operacao_centralizada_spec.rb`, `spec/integration/scan_solo/legacy_compatibility_spec.rb`, `spec/integration/scan_solo/acceptance_traceability_spec.rb`
      Mudança: fluxo completo (reply → callback → `awaiting_approval` → CT-05 → reply "aprovado" = `late_reply` → approve → e-mail com CC → `source_id` → `sent`/`proposta_enviada` → aviso + acompanhamento); rejeição → versão 2 na mesma conversa de proposta; resposta do lead por e-mail → interrupção total; resposta de `comercial@` sem efeito; cadeia de auditoria por `correlation_id`; 0 HTTP/SMTP reais; `config/schedule.yml` sem entradas novas; cenário (b) do `operacao_centralizada_spec.rb` atualizado citando RF-01/RF-11/RF-13; fixtures legadas legíveis; rastreabilidade RF-01..RF-26 e UI-01..UI-08.
      Cobre: RF-01..RF-26, RNF-01, RNF-02, RNF-03, RNF-04, RNF-06, RNF-10
      Acceptance criteria: os 4 specs verdes no container; a busca por `correlation_id` da solicitação devolve `proposal.generated`, `proposal.approval_requested`, `proposal.approved` (ou `proposal.rejected`), `proposal.sent`, `proposal.lead_email_reply` e `cadence.attempt_interrupted_by_reply`; 0 requisições externas reais (WebMock) e 0 SMTP real.
      Testes: os próprios arquivos.
- [ ] T33 — Documentação de arquitetura e contratos
      Arquivos: `docs/agents/domain_rules.md`, `docs/agents/architecture.md`, `docs/agents/data_model.md`, `docs/agents/api_contracts.md`
      Mudança: atualizar só as seções "Proposal lifecycle", "Proposal retry and dead letter", "Quote request and reply", "Cadence stop / recalculate", "Macro flow: quote to proposal", "Layer responsibilities", colunas/índices novos e os endpoints/webhook, com ponteiros para os 2 contratos desta feature; preservar as alterações locais já existentes.
      Cobre: CT-01..CT-09 (documentação)
      Acceptance criteria: `api_contracts.md` descreve `approve` como ativo e `send` bloqueado sem `proposal.send`, e aponta `openapi.yaml`/`asyncapi.yaml` desta feature; `domain_rules.md` lista os status 0–6; nenhuma seção fora das citadas alterada.
      Testes: revisão por `git diff <base> -- docs/agents`.

## Phase 14: Gates de qualidade

Antes de implementar, leia:
1. `.spec/features/scansolo-proposta-aprovacao-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-proposta-aprovacao-email/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T34 — Gates de qualidade e regressão
      Arquivos: nenhum arquivo novo; só correções residuais nos arquivos já alterados.
      Mudança: rubocop nos `.rb` alterados; `pnpm eslint` nos `.js/.vue` alterados (`.vue` explícitos); `pnpm test` nos specs tocados; `./scripts/ralph-test.sh`; checagens de RNF-03, RNF-05/RF-10, RNF-07, RNF-09, RNF-10, RF-21 e enterprise descritas no PLAN.
      Cobre: RNF-03, RNF-04, RNF-05, RNF-07, RNF-08, RNF-09, RNF-10, RF-10, RF-21
      Acceptance criteria: rubocop 0 offenses; eslint 0 erros; `./scripts/ralph-test.sh` exit 0; `git diff <base> --stat -- app/services/scan_solo/ai_turn/ app/services/scan_solo/actions/ app/services/whatsapp/ app/models/channel/whatsapp.rb db/seeds config/schedule.yml` vazio; `grep -nE "remove_column|rename_column|drop_table|change_column" db/migrate/20261007*` vazio; o grep de `skip|pending|xit` nos diffs de spec vazio; `request_send`/`'proposal.send'` só em `make_provider.rb`, `callback_handler.rb`, `callback_verifier.rb` e `callback_application_service.rb`; `grep -rnE "enterprise/|Captain::"` nos arquivos alterados vazio.
      Testes: os comandos acima.

## Phase 15: GATE HUMANO — HG-F, HG-G e HG-E (instância Chatwoot e Meta)

> NÃO executada pelo `ralph.sh`: fase de operador/humano (permissão do Luciano, teste real de SMTP e template Meta). Os checkboxes ficam para registro: só marcar `[x]` com a evidência descrita. Concluir antes da Phase 18.

Antes de implementar, leia:
1. `.spec/features/scansolo-proposta-aprovacao-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-proposta-aprovacao-email/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-proposta-aprovacao-email/asyncapi.yaml` — `proposalLeadEmail` (CT-06) e `proposalLeadNotice` (CT-07)

- [ ] T35 — GATE HUMANO HG-F: usuário do Luciano autorizado
      Arquivos: `.spec/features/scansolo-operacao-centralizada/make/REGISTRO.md`
      Mudança: tarefa humana. Confirmar em produção que o usuário do Luciano é administrador da conta ou está publicado como `commercial_user_id`; registrar data, conta e a condição válida.
      Cobre: HG-F, RF-04, RF-05, RF-15
      Acceptance criteria: `GET .../scan_solo/ai_agent_config` com `published.commercial_user_id` = id do Luciano, ou papel `administrator` dele; linha datada no `REGISTRO.md`.
      Testes: consulta registrada no `REGISTRO.md`.
- [ ] T36 — GATE HUMANO HG-G: SMTP do inbox de orçamento com CC e PDF
      Arquivos: `.spec/features/scansolo-operacao-centralizada/make/REGISTRO.md`
      Mudança: tarefa humana. Enviar 1 e-mail real de teste pelo inbox `quote_inbox_id` com `cc_emails` e 1 PDF anexo para um endereço de teste com cópia para `comercial@scansolo.com.br`; conferir To, Cc, anexo e `source_id`.
      Cobre: HG-G, RF-11, CT-06
      Acceptance criteria: `REGISTRO.md` com data, id da mensagem, `source_id` não nulo e confirmação de recebimento pelos 2 destinatários com o PDF íntegro.
      Testes: evidência registrada.
- [ ] T37 — GATE HUMANO HG-E: template Meta do aviso e mapeamento do slot
      Arquivos: `.spec/features/scansolo-operacao-centralizada/make/REGISTRO.md`
      Mudança: tarefa humana. Criar e aprovar na Meta o template "proposta enviada para seu e-mail" (sem cabeçalho de documento, sem link, `pt_BR`), sincronizar no inbox WhatsApp e mapear o slot `proposta_aviso_email` na tela de Templates; `scansolo_proposal_send` intacto.
      Cobre: HG-E, CT-07, RF-11
      Acceptance criteria: `GET .../cadence_templates` com a linha `proposta_aviso_email` `availability: available`; nome e status Meta registrados.
      Testes: consulta registrada.

## Phase 16: GATE HUMANO HG-D ampliado — backup de 8 cenários e estrutura de 2 data stores

> NÃO executada pelo `ralph.sh`: fase de operador/humano (exportação via Make MCP e aprovação do desenvolvedor; substitui a OC/T36). Os checkboxes ficam para registro: só marcar `[x]` com a evidência descrita.

Antes de implementar, leia:
1. `.spec/features/scansolo-proposta-aprovacao-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-proposta-aprovacao-email/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T38 — GATE HUMANO HG-D ampliado: backup de 8 cenários e estrutura de 2 data stores (RF-27)
      Arquivos: `.spec/features/scansolo-operacao-centralizada/make/backups/<scenarioId>-<AAAAMMDD>.json` (8 novos), `.spec/features/scansolo-operacao-centralizada/make/backups/datastore-<id>-structure-<AAAAMMDD>.json` (2 novos), `.spec/features/scansolo-operacao-centralizada/make/REGISTRO.md`
      Mudança: tarefa humana, sem alterar cenário. Exportar (team 701134, pasta `scanSolo` 247121) os blueprints de 6406463, 6177829, 6019491, 6036802, 6177833, 5497443, 5325058 e 5237984; exportar só a estrutura de `ScanSOLO_Config` (158313) e `ScanSOLO_Proposta_Map` (158314); grep de segredos; registrar a aprovação explícita do desenvolvedor para T39/T40.
      Cobre: RF-27, HG-D, RNF-07, RNF-09
      Acceptance criteria: 10 arquivos novos em `make/backups/` (8 blueprints + 2 estruturas); `grep -lE "Bearer [A-Za-z0-9]|\"secret\"\s*:\s*\"[^{]|hook\.[a-z0-9]+\.make\.com/[A-Za-z0-9]"` nos 10 arquivos vazio; `REGISTRO.md` com a aprovação datada.
      Testes: `ls .spec/features/scansolo-operacao-centralizada/make/backups/` e o grep acima.

## Phase 17: Make — legados desativados e `Entrada` adaptada (inativa)

> NÃO executada pelo `ralph.sh`: fase de operador/humano (alterações no Make via MCP, só com o backup e a aprovação registrados na Phase 16; substitui as OC/T37 e OC/T38). Os checkboxes ficam para registro: só marcar `[x]` com a evidência descrita.

Antes de implementar, leia:
1. `.spec/features/scansolo-proposta-aprovacao-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-proposta-aprovacao-email/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-proposta-aprovacao-email/asyncapi.yaml` — `makeIntegrationCallback` (CT-08, exemplo `generateSuccessWithChecksum`)
4. `.spec/features/scansolo-operacao-centralizada/asyncapi.yaml` — CT-05 (request) e CT-06 (callback base)

- [ ] T39 — Make: desativar os legados, sem apagar (RF-28)
      Arquivos: `.spec/features/scansolo-operacao-centralizada/make/REGISTRO.md`
      Mudança: tarefa humana. Com T38 aprovada, desativar (nunca apagar) 6177829, 6036802, 6019491, 5497443 e 6177833; confirmar 5325058 e 5237984 inativos e não apagados; registrar estado anterior e data.
      Cobre: RF-28, RNF-07
      Acceptance criteria: listagem do Make com os 7 legados `isActive: false` e os 8 cenários ainda existentes; `REGISTRO.md` com as linhas de desativação.
      Testes: listagem via Make MCP registrada.
- [ ] T40 — Make: `Entrada` adaptada ao CT-05/CT-06 + CT-08, inativa (RF-28)
      Arquivos: `.spec/features/scansolo-operacao-centralizada/make/REGISTRO.md`
      Mudança: tarefa humana. Com T38 aprovada e o cenário inativo: aplicar `OC/RF-47..RF-50`, `total_value` = `commercial.total_value` recebido e, opcionalmente, `artifact_sha256`/`template_version`; sem e-mail, Form ou envio ao cliente/comercial pelo Make.
      Cobre: RF-28, CT-08, RNF-07
      Acceptance criteria: "Run once" com o exemplo do `asyncapi.yaml` → callback com `total_value` igual e 0 e-mails enviados pelo Make; 2 execuções do mesmo `pv_` → mesmo `artifact_url`; cenário `isActive: false`; execuções registradas.
      Testes: execuções registradas no `REGISTRO.md`.

## Phase 18: GATE HUMANO HG-03 — deploy do Rails, ativação da `Entrada` e smoke

> NÃO executada pelo `ralph.sh`: fase de operador/humano (deploy confirmado, HG-03 pelo desenvolvedor, ativação no Make via MCP e smoke em produção; substitui a OC/T39). Os checkboxes ficam para registro: só marcar `[x]` com a evidência descrita.

Antes de implementar, leia:
1. `.spec/features/scansolo-proposta-aprovacao-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-proposta-aprovacao-email/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-proposta-aprovacao-email/asyncapi.yaml` — fluxo completo para o smoke

- [ ] T41 — GATE HUMANO HG-03: Rails em produção antes de ativar a `Entrada` e smoke (RF-29)
      Arquivos: `.spec/features/scansolo-operacao-centralizada/make/REGISTRO.md`
      Mudança: tarefa humana. 1) Registrar o deploy em produção das Phases 3–14 (commit e horário). 2) HG-03: fingerprint das credenciais `scan_solo.make.*` contra o `ScanSOLO_Config` (só hashes truncados), com T35–T37 concluídas. 3) Ativar a `Entrada` só depois. 4) Smoke com contato de teste: CT-04 → callback → `awaiting_approval` → e-mail ao Luciano com PDF → Aprovar na tela → e-mail ao lead com CC → `proposta_enviada` → aviso WhatsApp → resposta do lead por e-mail → `proposal.lead_email_reply`.
      Cobre: RF-29, HG-03, RNF-07
      Acceptance criteria: `REGISTRO.md` com horário do deploy < confirmação HG-03 < ativação da `Entrada`; listagem do Make com a `Entrada` ativa; auditorias do smoke pelo `correlation_id` registradas.
      Testes: evidências registradas no `REGISTRO.md`.
