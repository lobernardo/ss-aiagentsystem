# Phases: scansolo-operacao-centralizada

Gerado por /plan a partir de PLAN.md — view executável para `./ralph.sh .spec/features/scansolo-operacao-centralizada/PHASES.md`.

Regras transversais (de `AGENTS.md`/`CLAUDE.md`, `docs/agents/architecture.md`, `docs/agents/domain_rules.md`):
- Controllers: gate 404 `scansolo_enabled`, Pundit (403) e validação de borda (422). Services: regras, transações, locks e auditoria. Listener: só classifica e delega. Models: enums, associações e validações.
- `ScanSolo::Pipeline::StageTransitionService` é o único escritor de etapa. `FieldResolver` é o único leitor de "satisfeito". `CallbackHandler` é o único escritor de `value`/`currency`/`artifact_url`.
- RNF-01: chamada ao Make, download do PDF, mensagens WhatsApp novas e mensagens de e-mail só depois do commit (`ActiveRecord.after_all_transactions_commit` ou job).
- Reusar o nativo: `ContactInboxBuilder`, `ContactInboxWithContactBuilder`, `ConversationBuilder`, `ConversationReplyMailer` (via `Message`), `SafeFetch`, ActiveStorage e `NativeTemplateSender`. Sem SMTP, IMAP ou HTTP próprio com a Meta.
- Migrações só aditivas. Sem colunas em tabelas do Chatwoot. 0 referências a `enterprise/`/`Captain::`.
- i18n: backend em `config/locales/en.yml` (seção `scan_solo`); frontend em `app/javascript/dashboard/i18n/locale/en/scansolo.json`. Sem strings soltas.
- Estilo: classe compacta `class ScanSolo::...`, 1 classe por arquivo, ≤150 colunas, header comment com RF/CT/RNF. Vue com `<script setup>`, Tailwind e `components-next/`.
- Specs Ruby e rubocop: `docker exec scansolo-phase2-test sh -c 'cd /app && bundle exec rspec <paths>'` (idem `bundle exec rubocop <paths>`). Depois da Phase 1: `docker exec scansolo-phase2-test sh -c 'cd /app && RAILS_ENV=test bundle exec rails db:migrate'`. Vitest: `pnpm test <paths>`. ESLint com os `.vue` explícitos.
- RNF-11: um spec existente só muda de expectativa quando reflete mudança intencional do SPEC, citando o requisito na task. Nunca flexibilizar, remover ou pular (`skip`/`pending`/`xit`) um teste para fazê-lo passar.
- As Phases 7, 16, 17, 18 e 19 NÃO são executadas pelo `ralph.sh`: são de operador/humano (configuração Chatwoot/Meta, Make via MCP com aprovação do desenvolvedor, verificação com evidência). Os checkboxes ficam para registro e só são marcados `[x]` com a evidência descrita.

## Phase 8: Solicitação de orçamento e geração com dados comerciais

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-operacao-centralizada/asyncapi.yaml` — `quoteRequestEmail` (CT-03), `MakeIntegrationRequestPayload`/`Commercial` (CT-05)
4. `.spec/features/scansolo-operacao-centralizada/openapi.yaml` — `generateProposal` (RF-25)

- [ ] T19 — Solicitação de orçamento na conclusão + aviso único ao cliente
      Arquivos: `app/services/scan_solo/quote/request_service.rb` (novo), `app/jobs/scan_solo/quote_request_job.rb` (novo), `app/services/scan_solo/lead_state/completion_service.rb`, `spec/services/scan_solo/quote/request_service_spec.rb` (novo), `spec/services/scan_solo/lead_state/completion_service_spec.rb`
      Mudança:
        • `CompletionService`: com próxima ação `proposta`, `after_all_transactions_commit` → `QuoteRequestJob`.
        • `RequestService` (também expõe `deliver!(quote_request:, settings:)`, reusado por T40):
          1. revalida `concluida` + `proposta`;
          2. `Mailbox.resolve!` (inbox + destinatário publicado) (falha → auditoria `quote_request.misconfigured` + exceção, sem registros);
          3. transação com `opportunity.lock!` (mesmo lock do reenvio): `QuoteRequest.create!` (índice único) + `EmailThread.open!`;
          4. depois do commit: `post!` do `EmailComposer.request`, `request_message_id`/`sent_at` e auditoria `quote_request.sent` com o `correlation_id`;
          5. aviso RF-53 com o texto exato do i18n, só em `awaiting_reply` com e-mail criado, uma única vez (`customer_notice_message_id`, origem `quote_notice`), depois do commit; nunca repetido em turnos, reprocessamentos ou reenvios.
      Cobre: RF-12, RF-13, RF-14, RF-15, RF-16, RF-22, RF-53, RNF-01, RNF-02, RNF-03, RNF-09
      Acceptance criteria:
        • `proposta` → 1 solicitação, 1 conversa de e-mail e 1 mensagem com `to_emails` = [destinatário publicado] (trocado no publicado → novo endereço; só no rascunho → o publicado), assunto CT-03 e From do canal;
        • `duvida`/`avaliacao_tecnica`/`localizar_rede` → 0; as 3 condições do RF-14 → 0 mensagens, 1 auditoria, 1 exceção e `LeadState` `concluida`;
        • 2 jobs → 1 solicitação/1 e-mail; tentativa com rollback → 0 jobs; backfill → 0;
        • 1 aviso com o texto exato, `scansolo_origin: quote_notice` e `ai_active`; 2 turnos seguintes e job repetido → continua 1; mal configurado → 0 avisos;
        • nenhum envio com `transaction_open?`.
      Testes: `request_service_spec.rb`, `completion_service_spec.rb` — disparo, idempotência, configuração e aviso.
- [ ] T20 — Geração com dados comerciais (CT-05) e IA sem `proposal_generate`
      Arquivos: `app/services/scan_solo/proposal/generate_service.rb`, `app/services/scan_solo/proposal/make_provider.rb`, `app/services/scan_solo/qualification/field_resolver.rb`, `app/services/scan_solo/ai_turn/input_guardrail.rb`, `app/services/scan_solo/actions/proposal_actions.rb`, `app/controllers/api/v1/accounts/scan_solo/proposals_controller.rb`, `spec/services/scan_solo/proposal/generate_service_spec.rb`, `spec/services/scan_solo/proposal/make_provider_spec.rb`, `spec/services/scan_solo/ai_turn/input_guardrail_spec.rb`, `spec/requests/api/v1/accounts/scan_solo/proposals_spec.rb`
      Mudança:
        • `GenerateService(quote_request:)`: exige solicitação `replied`, da oportunidade e sem versão (senão `RecordInvalid` → 422); cria a versão com `quote_request_id`; gate de campos mantido.
        • Controller e handler da ação passam `opportunity.quote_request`.
        • `InputGuardrail` tira `proposal_generate` das ofertadas.
        • `MakeProvider`: `proposal_number` + `commercial` (com `total_value_in_words` e `quote_request_id`).
        • `make_qualification`: `projeto` = `cliente_final` quando presente.
      Cobre: RF-24, RF-25, RF-26, RF-28, CT-05, RNF-02, RNF-05
      Acceptance criteria: sem solicitação ou `awaiting_reply` → `RecordInvalid` e 0 versões; `replied` → 1 versão `generating` com `quote_request_id`; 2ª chamada/2 threads → 1 versão; payload com `commercial.total_value`, `total_value_in_words` (`12500.00` → "doze mil e quinhentos reais", 0 chamadas LLM), `proposal_number`, `idempotency_key` = `correlation_id` e `qualification.projeto`; chaves atuais iguais; `proposal_generate` fora das ofertadas e demais iguais; `POST .../generate` sem resposta validada → 422; specs existentes alterados citam RF-25/RF-24/CT-05 (RNF-11).
      Testes: os 4 specs listados — gate, payload, ofertas e endpoint.

## Phase 9: Retorno do orçamento, publicador de notificação e reenvio manual

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-operacao-centralizada/asyncapi.yaml` — `quoteReplyEmail` (CT-04), `negotiationRequested` (CT-07), `nativeMessageCreated`
4. `.spec/features/scansolo-operacao-centralizada/openapi.yaml` — `resendQuoteRequest` (CT-12) e `PipelineOpportunityDetail.quote_request_resend_available`

- [ ] T21 — Processamento da resposta do Luciano e roteamento no listener
      Arquivos: `app/services/scan_solo/quote/reply_processor.rb` (novo), `app/jobs/scan_solo/quote_reply_job.rb` (novo), `app/services/scan_solo/conversation_listener.rb`, `spec/services/scan_solo/quote/reply_processor_spec.rb` (novo), `spec/services/scan_solo/conversation_listener_spec.rb`
      Mudança:
        • Listener: `incoming` de inbox de e-mail igual ao `quote_inbox_id` publicado → `QuoteReplyJob`, antes do gate de elegibilidade.
        • Processor: thread de negociação → ignora; sem solicitação → `QuoteReply unmatched`; solicitação `replied` → `late_reply`; senão `.apply`.
        • `.apply`: parser válido → `replied` + `commercial` + auditoria e, depois do commit, `GenerateService` + auditoria `proposal.generation_requested`; inválido → `correction_requested` + correção na thread da solicitação, depois do commit.
      Cobre: RF-16, RF-17, RF-18, RF-19, RF-21, RF-22, RF-23, RF-24, RF-42, RNF-01, RNF-03, RNF-09
      Acceptance criteria:
        • bloco válido → `replied`, `12500.00`, 1 versão, 1 `MakeRequest` com `commercial.total_value` e 0 HTTP antes do commit;
        • inválido → 0 versões + 1 correção na mesma conversa com o rótulo e o bloco;
        • sem cabeçalhos → 1 `unmatched`;
        • `replied` + versão `generating`/`sent` → 1 `late_reply`, 0 versões, 0 `MakeRequest` e 0 WhatsApp;
        • reply de negociação → 0 pendentes;
        • 0 chamadas LLM;
        • cadeia RF-22 navegável pelo id da oportunidade com o mesmo `correlation_id`;
        • inbox de orçamento → 0 `PipelineOpportunity`/`AiTurn`/`ConversationExtension`; WhatsApp sem query de config a mais.
      Testes: `reply_processor_spec.rb`, `conversation_listener_spec.rb` — roteamento e os ramos acima.
- [ ] T22 — Publicador de notificação (CT-07) e adaptador de e-mail
      Arquivos: `app/services/scan_solo/notifications/publisher.rb` (novo), `app/services/scan_solo/notifications/email_adapter.rb` (novo), `app/services/scan_solo/notifications/negotiation_payload.rb` (novo), `spec/services/scan_solo/notifications/publisher_spec.rb` (novo), `spec/services/scan_solo/notifications/email_adapter_spec.rb` (novo), `spec/services/scan_solo/notifications/negotiation_payload_spec.rb` (novo)
      Mudança:
        • `NegotiationPayload.build` monta exatamente o CT-07.
        • `Publisher.call(event:, payload:, adapters: ADAPTERS)`: falha ou exceção → auditoria `negotiation.notification_failed` + exceção capturada, sem propagar; sucesso → `negotiation.notification_sent`.
        • `EmailAdapter`: destinatário publicado (`Mailbox.resolve!`), thread própria com marcador `negotiation_notification` + `EmailComposer.negotiation`; inbox mal configurado → `success: false`.
      Cobre: CT-07, RF-37, RF-39, RF-41, RF-42
      Acceptance criteria: payload com chaves e tipos do CT-07 (`proposal`/`current_value` nulos sem proposta, ≤ 3 mensagens); adaptador de teste recebe payload idêntico; adaptador que levanta → 1 auditoria + 1 exceção, sem propagar; e-mail com os 9 itens e o link; inbox ausente → falha registrada.
      Testes: os 3 specs listados — payload, publicador e adaptador.
- [ ] T40 — Reenvio manual auditado e idempotente da solicitação de orçamento (RF-56, CT-12)
      Arquivos: `app/services/scan_solo/quote/resend_service.rb` (novo), `app/controllers/api/v1/accounts/scan_solo/quote_requests_controller.rb` (novo), `app/policies/scan_solo/quote_request_policy.rb` (novo), `config/routes.rb`, `app/views/api/v1/accounts/scan_solo/pipeline_opportunities/show.json.jbuilder`, `lib/custom_exceptions/scan_solo.rb`, `spec/services/scan_solo/quote/resend_service_spec.rb` (novo), `spec/requests/api/v1/accounts/scan_solo/quote_request_resend_spec.rb` (novo)
      Mudança:
        • Rota `POST pipeline_opportunities/:id/quote_request/resend` → `quote_requests#resend`; policy só `administrator?`.
        • `ResendService.available?(opportunity)`: solicitação aberta, ou sem solicitação com `concluida` + `proposta` + auditoria `quote_request.misconfigured`.
        • `ResendService.call`: `Mailbox.resolve!` (inválida → auditoria RF-14 + 422 `quote_inbox_misconfigured`); sob `opportunity.lock!`: `replied` → `quote_request_closed`; aberta → reusa solicitação, conversa e `correlation_id`; caso 2 → cria a única solicitação (caminho do T19); senão `quote_request_not_eligible`.
        • Depois do commit: `RequestService#deliver!` para o destinatário publicado; status inalterado; aviso RF-53 só se nunca enviado; auditoria `quote_request.resent` (ator, destinatário, `correlation_id`).
        • 200 `{ quote_request_id, status, correlation_id, recipient, resent_at }`; `show` ganha `quote_request_resend_available`.
      Cobre: RF-56, CT-12, CT-02, RF-15, RF-53, RNF-01, RNF-02, RNF-09
      Acceptance criteria: `awaiting_reply` → 1 nova mensagem na mesma conversa, 0 solicitações novas, mesmo `correlation_id` e 1 auditoria com o ator; destinatário publicado trocado → `to_emails` novo; `misconfigured` + config corrigida → 1 solicitação, 1 e-mail e 1 aviso; solicitação que já teve aviso → continua 1; `replied` → 422 `quote_request_closed` e 0 mensagens; concluída antes do deploy sem auditoria → 422 `quote_request_not_eligible`; config inválida → 422 `quote_inbox_misconfigured`; 2 reenvios concorrentes → 1 solicitação; não admin → 403; flag off → 404; `available?` correto nos 4 casos.
      Testes: `quote_request_resend_spec.rb`, `resend_service_spec.rb` — endpoint, idempotência e concorrência.

## Phase 10: Pendentes de vínculo, entrega e acompanhamento

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-operacao-centralizada/openapi.yaml` — `quote_replies` (CT-08), `retryProposal` (CT-10)
4. `.spec/features/scansolo-operacao-centralizada/asyncapi.yaml` — `makeIntegrationCallback` (CT-06), `nativeMessageUpdated`

- [ ] T23 — API de pendentes de vínculo (CT-08)
      Arquivos: `config/routes.rb`, `app/controllers/api/v1/accounts/scan_solo/quote_replies_controller.rb` (novo), `app/policies/scan_solo/quote_reply_policy.rb` (novo), `app/services/scan_solo/quote/pending_reply_resolution.rb` (novo), `app/views/api/v1/accounts/scan_solo/quote_replies/index.json.jbuilder` (novo), `app/views/api/v1/accounts/scan_solo/quote_replies/_quote_reply.json.jbuilder` (novo), `spec/requests/api/v1/accounts/scan_solo/quote_replies_spec.rb` (novo), `spec/services/scan_solo/quote/pending_reply_resolution_spec.rb` (novo)
      Mudança:
        • Rotas `index`, `link` e `discard`; policy admin ou membro do inbox de orçamento.
        • `index?status=pending`.
        • `link!` com lock: `already_linked`/`quote_request_closed`; senão `linked` + auditoria com ator e, depois do commit, `ReplyProcessor.apply`.
        • `discard!`: `already_discarded`; `unmatched` → `not_discardable`; senão `discarded` + auditoria.
        • Borda: `invalid_quote_request_id`.
      Cobre: CT-08, RF-19, RF-20, RF-23, RNF-09
      Acceptance criteria:
        • lista com os campos do CT-08; agente sem acesso → 403; flag off → 404;
        • vínculo válido → `replied` + 1 versão; inválido → `correction_requested` + correção na thread da solicitação;
        • vincular de novo → 422 `already_linked`; `late_reply` ou solicitação `replied` → 422 `quote_request_closed`;
        • `discard` de `late_reply` → 200, fora da lista, 1 auditoria e 0 versões; repetido → `already_discarded`; `unmatched` → `not_discardable`;
        • 2 vínculos concorrentes → 1 processamento.
      Testes: `quote_replies_spec.rb`, `pending_reply_resolution_spec.rb` — endpoints e concorrência.
- [ ] T24 — Entrega da proposta pelo WhatsApp com PDF e reenvio sem Make (RF-29, RF-32, CT-10)
      Arquivos: `app/services/scan_solo/proposal/callback_handler.rb`, `app/services/scan_solo/make/callback_application_service.rb`, `app/services/scan_solo/proposal/delivery_service.rb` (novo), `app/jobs/scan_solo/proposal_delivery_job.rb` (novo), `app/services/scan_solo/proposal/retry_policy.rb`, `spec/services/scan_solo/proposal/delivery_service_spec.rb` (novo), `spec/services/scan_solo/proposal/callback_handler_spec.rb`, `spec/services/scan_solo/proposal/retry_policy_spec.rb`, `spec/requests/webhooks/scan_solo/make_spec.rb`
      Mudança:
        • O callback de sucesso grava `valid_until` e agenda `ProposalDeliveryJob` depois do commit.
        • `DeliveryService` com lock e idempotência por `sent_message_id`:
          • `SafeFetch` (só `application/pdf`) → `document.attach` (`<número>.pdf`);
          • slot `proposta_enviada` com `document:` + guard → `NativeTemplateSender` origem `proposal` → `sent_message`;
          • falhas → `failed` (`artifact_download_failed`/guard/`external_error`) + auditoria, preservando `value`/`artifact_url`/PDF.
        • `RetryPolicy`: `delivery_stage?` → `DeliveryService(retry: true)` sem `MakeRequest`; `retry_send!` removido.
      Cobre: RF-26, RF-27, RF-28, RF-29, RF-32, RF-33, CT-06, CT-10, RNF-01, RNF-02
      Acceptance criteria:
        • callback válido → `generated` com `value`/`valid_until`; inválidos → `generating`;
        • entrega → 1 blob PDF, header `media_url` = URL do blob (≠ `artifact_url`), `media_type: document`, `media_name` = `<número>.pdf`, `sent_message_id`; 0 `proposal.send`; 0 `ApproveService` com aprovação obrigatória e `approved_at` nulo;
        • HTTP 500/`text/html` → `artifact_download_failed`; guard → `failed`/motivo, etapa `qualificado` e 0 acompanhamentos;
        • 2 jobs → 1 mensagem; `retry` → 1 nova mensagem com o mesmo blob, 0 downloads e 0 `MakeRequest`;
        • download e envio fora de transação; `generated` não move etapa.
      Testes: os 4 specs listados — entrega, falhas, reenvio e callback.
- [ ] T25 — Aceite real, falha posterior e acompanhamento (RF-30, RF-31)
      Arquivos: `app/services/scan_solo/messaging/delivery_reconciler.rb`, `app/services/scan_solo/proposal/success_handler.rb`, `app/services/scan_solo/proposal/follow_up_service.rb` (novo), `spec/services/scan_solo/messaging/delivery_reconciler_spec.rb`, `spec/services/scan_solo/proposal/success_handler_spec.rb`, `spec/services/scan_solo/proposal/follow_up_service_spec.rb` (novo)
      Mudança:
        • Reconciliador: versão `sent` + mensagem `failed` → `failed` + auditoria, sem etapa nem matrícula.
        • `SuccessHandler` agenda `FollowUpService` depois do commit.
        • `FollowUpService` com lock (`sent` e `follow_up_message_id` nulo): slot `proposta_acompanhamento` + guard; envia origem `proposal_follow_up` e grava o id; bloqueado → auditoria.
      Cobre: RF-30, RF-31, RF-33, RNF-01, RNF-02
      Acceptance criteria: sem `source_id` → `generated` e etapa igual; `source_id` → `sent`, `proposta_enviada`, 1 `PipelineStageEvent` e 1 matrícula com offsets ativos; depois `failed` → versão `failed`, 1 auditoria e 0 eventos novos; 1 acompanhamento após `sent`; 2º `message_updated` → 1; versão `failed` → 0.
      Testes: os 3 specs listados — aceite, falha posterior e acompanhamento idempotente.

## Phase 11: Negociação

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-operacao-centralizada/asyncapi.yaml` — `negotiationRequested` (CT-07)

- [ ] T26 — Negociação: sinal, resposta padrão, etapa, handoff, notificação e atribuição (RF-35..RF-40)
      Arquivos: `app/services/scan_solo/negotiation/request_service.rb` (novo), `app/services/scan_solo/actions/lead_state_update_action.rb`, `app/services/scan_solo/ai_turn/attempt_runner.rb`, `app/services/scan_solo/ai_turn/prompt_builder.rb`, `spec/services/scan_solo/negotiation/request_service_spec.rb` (novo), `spec/services/scan_solo/actions/lead_state_update_action_spec.rb`, `spec/services/scan_solo/ai_turn/attempt_runner_spec.rb`, `spec/services/scan_solo/ai_turn/prompt_builder_spec.rb`, `spec/services/scan_solo/actions/stage_transition_action_spec.rb`
      Mudança:
        • `lead_state_update` ganha `negotiation_requested` (boolean, só evidência).
        • `PromptBuilder`: só `ACTION_DESCRIPTIONS['lead_state_update']` + 1 regra fixa.
        • `AttemptRunner`: sinal em `proposta_enviada`/`negociacao` → `Negotiation::RequestService` + `result` com texto padrão do i18n e `asked_fields: []`.
        • `RequestService`:
          1. `StageTransitionService(authorized: true)` só em `proposta_enviada`;
          2. `HandoffService` + `StopRecalculatePolicy(handoff)`;
          3. auditoria;
          4. depois do commit: `Publisher` com `NegotiationPayload` e atribuição nativa ao `commercial_user_id` quando membro do inbox (falha → auditoria + exceção).
      Cobre: RF-34, RF-35, RF-36, RF-37, RF-38, RF-39, RF-40, RF-41, RF-46, RNF-05
      Acceptance criteria:
        • `proposta_enviada` + sinal → texto padrão exato, `negociacao`, 1 `PipelineStageEvent`, `awaiting_human`, 1 nota privada, matrículas pausadas e 1 publicação depois do commit;
        • `negociacao` + `ai_active` → texto, handoff e notificação, 0 eventos de etapa;
        • `em_qualificacao` → nada muda e 0 notificações;
        • com `commercial_user_id` → `assignee_id`; sem → inalterado;
        • inbox ausente → `negociacao` + `awaiting_human` + 1 auditoria de falha + 1 exceção;
        • `stage_transition` para `negociacao` → `stage_not_allowed_for_ai`; `awaiting_human`/`human_active` → turno `human_controlled`.
      Testes: os 5 specs listados — com LLM mock.

## Phase 12: Frontend base — textos, API e stores

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-operacao-centralizada/openapi.yaml` — CT-01, CT-02, CT-08, CT-12

- [ ] T27 — Frontend base: textos, API e stores
      Arquivos: `app/javascript/dashboard/i18n/locale/en/scansolo.json`, `app/javascript/dashboard/api/scansoloPipelineOpportunities.js`, `app/javascript/dashboard/api/scansoloQuoteReplies.js` (novo), `app/javascript/dashboard/store/scansolo/pipelineOpportunities.js`, `app/javascript/dashboard/store/scansolo/quoteReplies.js` (novo), `app/javascript/dashboard/routes/dashboard/scansolo/scansoloLabels.js`, `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/pipelineConstants.js`, `app/javascript/dashboard/store/scansolo/specs/quoteReplies.spec.js` (novo), `app/javascript/dashboard/store/scansolo/specs/pipelineOpportunities.spec.js`
      Mudança:
        • Todas as chaves i18n de UI-01..UI-07, RF-54 (3 campos), slots e erros do CT-12 (`quote_request_closed`, `quote_request_not_eligible`, `quote_inbox_misconfigured`).
        • API `create`, `resendQuoteRequest(id)` (CT-12) e `quoteReplies` (`getPending`/`link`/`discard`).
        • Stores `createOpportunity` e `useScansoloQuoteRepliesStore`.
        • Constantes `LEAD_SOURCE_TAGS`/`LABELS`, `FIELD_STATUS_LABELS`, `commercialStatusKey` e `MS_PER_DAY`.
        • Os métodos `approve`/`send` de API e store não mudam (RF-55 Etapa 1); só saem em T32, se T41 comprovar ausência de uso.
      Cobre: RNF-08, UI-01, UI-02, UI-03, UI-04, UI-05, UI-06, UI-07, RF-33, RF-45
      Acceptance criteria: `createOpportunity` insere o card; `resendQuoteRequest` faz `POST .../pipeline_opportunities/:id/quote_request/resend`; `link`/`discard` removem a linha; `commercialStatusKey` em tabela (`generated`/`approved` → "Proposta gerada", nunca "enviada"; sem proposta usa o status da solicitação).
      Testes: `quoteReplies.spec.js`, `pipelineOpportunities.spec.js` — stores e mapeamento.

## Phase 13: Frontend — telas (inclui a desativação de Aprovar/Enviar, RF-55 Etapa 1)

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-operacao-centralizada/openapi.yaml` — CT-01, CT-02, CT-08, CT-12, `ai_agent_config`, `cadence_templates`

- [ ] T28 — Kanban: card enxuto, navegação e formulário "Novo lead" (UI-01, UI-02, UI-03)
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/KanbanBoard.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/NewLeadDialog.vue` (novo), `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/specs/KanbanBoard.spec.js`, `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/specs/NewLeadDialog.spec.js` (novo)
      Mudança:
        • Botão "Novo lead" no cabeçalho.
        • Card com origem, empresa ou contato, serviço, cidade/UF, "Sem interação há X dias" (X ≥ 1), status comercial e indicador humano.
        • Clique → detalhe (arrasto preservado).
        • `NewLeadDialog` (`components-next/`): validação E.164 local, inbox pré-selecionado com 1 inbox WhatsApp allowlisted, erros 422 por código e "Abrir oportunidade existente".
      Cobre: UI-01, UI-02, UI-03, RF-33
      Acceptance criteria: sem telefone → erro e 0 requisições; `contact_conflict` → mensagem i18n; `opportunity_exists` com `opportunity_id: 7` → `router.push` ao detalhe 7; 201 → card `novo_lead` com "COMERCIAL"; card sem empresa mostra o contato; −49 h → "Sem interação há 2 dias"; `awaiting_human` mostra o indicador e `ai_active` oculta; clique → `router.push` com `opportunityId`; arrasto igual; menu idêntico.
      Testes: `KanbanBoard.spec.js`, `NewLeadDialog.spec.js` — componente.
- [ ] T29 — Tela do lead (`OpportunityDetail`, UI-04, UI-07)
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/OpportunityDetail.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/specs/OpportunityDetail.spec.js`
      Mudança: origem, responsável, seções "Coletado"/"A confirmar"/"Faltante" a partir de `leadState.blocks`, status do orçamento (datas), status da proposta (versão, número, status, valor/validade quando `generated`/`sent`, link `documentUrl`) falha do template inicial com motivo e status (oculta quando `null`) e a ação UI-07 "Reenviar solicitação de orçamento" (só admin via `useScanSoloRole` e com `quoteRequestResendAvailable`), com sucesso/erro 422 por código e recarga do `show`.
      Cobre: UI-04, UI-07, RF-45, RF-08, RF-56
      Acceptance criteria: fixture do `show` → as 3 seções com os campos certos; origem, orçamento e proposta exibidos; `initialTemplateFailure` → motivo e status visíveis, `null` → oculto; admin com `quoteRequestResendAvailable: true` → ação visível e clique → POST do CT-12 + sucesso; não admin ou `false` → oculta; 422 `quote_request_closed` → mensagem i18n; textos só do i18n.
      Testes: `OpportunityDetail.spec.js` — componente.
- [ ] T30 — Tela de Propostas: pendentes de vínculo e desativação de Aprovar/Enviar (UI-05, UI-06, RF-55 Etapa 1)
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/proposals/Proposals.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/proposals/QuoteRepliesPending.vue` (novo), `app/javascript/dashboard/routes/dashboard/scansolo/proposals/specs/Proposals.spec.js`, `app/javascript/dashboard/routes/dashboard/scansolo/proposals/specs/QuoteRepliesPending.spec.js` (novo)
      Mudança:
        • Seção de pendentes: "Vincular" para `unmatched`, com escolha de solicitação aberta; "Descartar" + solicitação de origem para `late_reply`.
        • Deixa de exibir Aprovar/Enviar e de chamá-los na tela; store e API legados ficam intactos (RF-55 Etapa 1).
        • Mostra o status da solicitação, número, validade e link do PDF; "Reenviar" só em `failed`; histórico só leitura.
      Cobre: UI-05, UI-06, RF-55 (Etapa 1), RF-19, RF-20, RF-23
      Acceptance criteria: 2 pendentes → 2 linhas; "Vincular" → POST com ids certos e a linha some; vazio → estado vazio; `late_reply` → origem + "Descartar" → POST `discard` e some; versões `generated`/`approved`/`sent` → 0 botões Aprovar/Enviar e status exibidos; `failed` → "Reenviar"; `grep -n "approveProposal\|sendProposal" routes/dashboard/scansolo` vazio; testes de clique em aprovar/enviar trocados pela ausência dos botões, citando RF-55/UI-06 (RNF-11).
      Testes: `Proposals.spec.js`, `QuoteRepliesPending.spec.js` — componente.
- [ ] T31 — Configuração e Templates: 3 campos, sem toggle, rótulos dos slots (RF-54, UI-06)
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/agent/AgentCenter.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/agent/agentCenterFields.js`, `app/javascript/dashboard/routes/dashboard/scansolo/followups/TemplatesPanel.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/agent/specs/AgentCenter.spec.js`, `app/javascript/dashboard/routes/dashboard/scansolo/followups/specs/TemplatesPanel.spec.js`
      Mudança: remove o toggle `requireProposalApproval` (sem enviá-lo); acrescenta os selects `quoteInboxId` (inboxes de e-mail) e `commercialUserId` (agentes) e o campo `quoteRecipientEmail` (obrigatório, validação de e-mail); `TemplatesPanel` rotula `lead_manual_inicial` e `proposta_acompanhamento`.
      Cobre: RF-54, UI-06, CT-09
      Acceptance criteria: 0 toggles de aprovação; os 3 campos visíveis e enviados ao salvar; destinatário vazio → erro de campo e 0 requisições; `require_proposal_approval` não enviado; itens do menu ScanSolo idênticos; 2 linhas de slot com rótulo.
      Testes: `AgentCenter.spec.js`, `TemplatesPanel.spec.js` — componente.

## Phase 14: Provas ponta a ponta e documentação

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-operacao-centralizada/openapi.yaml` e `.spec/features/scansolo-operacao-centralizada/asyncapi.yaml` — contratos a referenciar na documentação

- [ ] T33 — Provas ponta a ponta e RNF transversais
      Arquivos: `spec/integration/scan_solo/operacao_centralizada_spec.rb` (novo), `spec/integration/scan_solo/legacy_compatibility_spec.rb` (novo), `spec/integration/scan_solo/acceptance_traceability_spec.rb`
      Mudança: cenários com mocks de LLM e Make, WebMock e ActionMailer `:test`:
        • (a) lead manual → qualificação → e-mail + aviso;
        • (b) correção → resposta válida → callback assinado → PDF → template → aceite → `proposta_enviada` + acompanhamento;
        • (c) negociação;
        • (d) pendente → vínculo → geração;
        • (e') inbox mal configurado → config corrigida e publicada → reenvio CT-12 → 1 solicitação, 1 e-mail, 1 aviso; 2º reenvio → mesma solicitação e 1 aviso;
        • (e) cadeia de auditorias pelo `correlation_id`;
        • (f) 0 HTTP/SMTP reais.
        • Mais: fixtures legadas sem erro e rastreabilidade dos ids.
      Cobre: RF-11, RF-22, RF-34, RF-55 (Etapa 1), RF-56, RNF-01, RNF-02, RNF-04, RNF-09, RNF-10
      Acceptance criteria: os 7 cenários passam; 0 chamadas a `ApproveService`/`SendService` e 0 `MakeRequest` `proposal.send` no fluxo novo; uma busca por `correlation_id` da solicitação devolve envio, resposta, geração, callback e entrega; fixtures legadas → 0 erros nos `GET`.
      Testes: os 3 arquivos listados.
- [ ] T34 — Documentação de arquitetura e contratos
      Arquivos: `docs/agents/domain_rules.md`, `docs/agents/architecture.md`, `docs/agents/data_model.md`, `docs/agents/api_contracts.md`
      Mudança: atualizar só as seções citadas no PLAN (pipeline, cadência, proposta, guardrails, registry, handoff, "Quote request" com reenvio RF-56, fluxos, tabelas, endpoints com CT-12 e CT-11 desativado) com ponteiros para `openapi.yaml`/`asyncapi.yaml` desta feature.
      Cobre: CT-01, CT-02, CT-03, CT-04, CT-05, CT-06, CT-07, CT-08, CT-09, CT-10, CT-11, CT-12
      Acceptance criteria: `docs/agents/api_contracts.md` aponta para os 2 contratos; `domain_rules.md` descreve a interrupção ≤ 1 por ciclo, a solicitação de orçamento approve/send desativados (não removidos) e o reenvio manual; `approve`/`proposal.send` só em contexto histórico.
      Testes: `grep -n "scansolo-operacao-centralizada" docs/agents/api_contracts.md` com 2 ou mais linhas.

## Phase 15: Gates de qualidade

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T35 — Gates de qualidade e regressão
      Arquivos: nenhum arquivo novo (corrige só quebras residuais nos arquivos já alterados)
      Mudança:
        • rubocop nos `.rb` alterados; `pnpm eslint` com os `.js`/`.vue` explícitos; `pnpm test` nos specs tocados; `./scripts/ralph-test.sh`.
        • Checagens RNF-05: diff de `ai_turn/` restrito a `attempt_runner.rb`, `prompt_builder.rb` e `input_guardrail.rb`; `output_validator.rb` sem diff.
        • RNF-10/RF-44: sem `remove_*`, seeds de cadência intactos, 6 estados de controle.
        • RNF-11: `git diff main -- spec app/javascript` sem `skip`/`pending`/`xit`/`it.skip` novos; cada spec existente alterado citado numa task com o requisito.
        • RF-55 Etapa 1: nenhuma tela chama `approveProposal`/`sendProposal`; rotas `approve`/`send` ainda presentes.
        • RNF-07 (sem segredos literais) e enterprise (0 referências).
      Cobre: RNF-04, RNF-05, RNF-07, RNF-08, RNF-10, RNF-11, RF-44, RF-46, RF-55
      Acceptance criteria: rubocop 0 offenses; eslint 0 erros; `./scripts/ralph-test.sh` exit 0; os greps de RNF-05/RNF-07/RNF-10/RNF-11/RF-44/RF-55/enterprise retornam o esperado no PLAN.
      Testes: comandos acima.

