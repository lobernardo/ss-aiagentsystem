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
- Base de comparação da feature: `8a168c0590` (`docs(spec): plano scansolo-operacao-centralizada`), o commit de primeiro pai imediatamente anterior ao 1º commit de código (`3eaed50351`) e que só altera `.spec/`. Todo `git diff <base>` desta feature usa esse commit. `main` não tem ancestral comum com esta branch, e `origin/feat/release-2026-09-25` (merge-base `c100e87d83`) inclui o lead-state e o ciclo 1, que não são desta feature e acusariam falsos diffs em `ai_turn/` e nos specs.
- As Phases 7, 16, 17, 18 e 19 NÃO são executadas pelo `ralph.sh`: são de operador/humano (configuração Chatwoot/Meta, Make via MCP com aprovação do desenvolvedor, verificação com evidência). Os checkboxes ficam para registro e só são marcados `[x]` com a evidência descrita.

## Phase 1: Fundação de dados — migrações aditivas

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos

- [x] T01 — Migrações aditivas da feature
      Arquivos: `db/migrate/20261001000001_add_lead_source_to_scan_solo_pipeline_opportunities.rb`, `db/migrate/20261001000002_create_scan_solo_quote_requests.rb`, `db/migrate/20261001000003_create_scan_solo_quote_replies.rb`, `db/migrate/20261001000004_add_delivery_columns_to_scan_solo_proposal_versions.rb`, `db/migrate/20261001000005_add_commercial_settings_to_scan_solo_ai_agent_configs.rb` (novos), `db/schema.rb`
      Mudança:
        • `lead_source` string nullable com check `IN ('website','manual')`.
        • `scan_solo_quote_requests`: `account_id`, `opportunity_id` único, `email_conversation_id` único nullable, `request_message_id`, `reply_message_id`, `customer_notice_message_id`, `status` int default 0, `correlation_id` único not null, `commercial` jsonb `{}`, `sent_at`, `replied_at`, timestamps.
        • `scan_solo_quote_replies`: `account_id`, `message_id` único not null, `conversation_id`, `quote_request_id`, `kind`, `status` default 0, `resolved_by_id`, `resolved_at`, timestamps, índice `(account_id, status)`.
        • `scan_solo_proposal_versions`: `proposal_number` (único), `valid_until` datetime, `follow_up_message_id`, `quote_request_id` (FK, único).
        • `scan_solo_ai_agent_configs`: `quote_inbox_id`, `commercial_user_id` (null, sem default) e `quote_recipient_email` (`null: false, default: 'comercial@scansolo.com.br'`).
        • Nada de `remove_*`/`rename_*`/`change_column`.
      Cobre: RF-01, RF-15, RF-19, RF-22, RF-23, RF-26, RF-29, RF-31, RF-54, RNF-02, RNF-05, RNF-10
      Acceptance criteria: `db:migrate` no container de teste sem erro; `db/schema.rb` com as 2 tabelas e as colunas/índices únicos listados; `quote_recipient_email` = `comercial@scansolo.com.br` no rascunho e nas versões publicadas existentes; `grep -nE "remove_column|rename_column|drop_table|change_column|remove_index" db/migrate/20261001*` vazio; nenhum `UPDATE` de valores existentes.
      Testes: `docker exec scansolo-phase2-test sh -c 'cd /app && RAILS_ENV=test bundle exec rails db:migrate'` — migração limpa.

## Phase 2: Modelos, configuração, slots de template e textos

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-operacao-centralizada/openapi.yaml` — `ai_agent_config` (RF-54) e `cadence_templates` (slots CT-09)

- [x] T02 — Modelos `QuoteRequest`/`QuoteReply` e associações da oportunidade
      Arquivos: `app/models/scan_solo/quote_request.rb` (novo), `app/models/scan_solo/quote_reply.rb` (novo), `app/models/scan_solo/pipeline_opportunity.rb`, `spec/models/scan_solo/quote_request_spec.rb` (novo), `spec/models/scan_solo/quote_reply_spec.rb` (novo), `spec/models/scan_solo/pipeline_opportunity_spec.rb`
      Mudança:
        • `QuoteRequest`: enum `awaiting_reply/correction_requested/replied`, associações (`opportunity`, `account`, `email_conversation`, `reply_message`, `has_one :proposal_version`), `open?`.
        • `QuoteReply`: enums `kind` (`unmatched/late_reply`) e `status` (`pending/linked/discarded`).
        • `PipelineOpportunity`: `LEAD_SOURCES`, validação de `lead_source` (allow_nil), `has_one :quote_request` e `has_one :conversation_extension` (`primary_key`/`foreign_key: :conversation_id`).
      Cobre: RF-01, RF-15, RF-19, RF-22, RF-23, CT-02
      Acceptance criteria: 2ª solicitação na mesma oportunidade → `RecordNotUnique`; `message_id` duplicado em `QuoteReply` → `RecordNotUnique`; `lead_source: 'site'` inválido e `nil`/`website`/`manual` válidos; `opportunity.conversation_extension` resolve pela conversa.
      Testes: os 3 specs de modelo — unicidade, enums, validação e associação.
- [x] T03 — `ProposalVersion`: número, validade, PDF e vínculo com a solicitação
      Arquivos: `app/models/scan_solo/proposal_version.rb`, `spec/models/scan_solo/proposal_version_spec.rb`
      Mudança: `has_one_attached :document`, `belongs_to :quote_request`/`:follow_up_message` (optional), `after_create` que grava `proposal_number = format('SS-%<year>d-%<id>06d', …)` e `document_url` (`rails_blob_url` com host `FRONTEND_URL`, ou nil).
      Cobre: RF-26, RF-29, CT-02, CT-09
      Acceptance criteria: 2 versões → 2 números distintos no formato `SS-AAAA-NNNNNN`; com PDF anexado, `document_url` começa com `FRONTEND_URL` e ≠ `artifact_url`; sem documento → nil.
      Testes: `spec/models/scan_solo/proposal_version_spec.rb` — número, `document_url`.
- [x] T04 — Configuração RF-54 no backend (3 campos)
      Arquivos: `app/models/scan_solo/ai_agent_config.rb`, `app/controllers/api/v1/accounts/scan_solo/ai_agent_configs_controller.rb`, `app/views/api/v1/accounts/scan_solo/ai_agent_configs/_ai_agent_config.json.jbuilder`, `spec/requests/api/v1/accounts/scan_solo/ai_agent_configs_spec.rb`
      Mudança:
        • `FIELDS` ganha `quote_inbox_id`/`commercial_user_id`/`quote_recipient_email` (snapshot de publicação; fluxos leem só o publicado); `draft_params` permite os 3; `require_proposal_approval` continua aceito.
        • Borda 422: inbox não-e-mail, de outra conta ou na `allowed_inbox_ids` efetiva; usuário fora da conta; `allowed_inbox_ids` contendo o `quote_inbox_id`; destinatário vazio ou malformado.
        • jbuilder com as 3 chaves.
      Cobre: RF-54, RF-14, RF-16, RNF-05
      Acceptance criteria: salvar e publicar → os 3 valores em `draft` e `published`; cada condição inválida (inclusive destinatário vazio/malformado) → 422; destinatário editado só no rascunho não muda o publicado; exemplos existentes verdes.
      Testes: `spec/requests/api/v1/accounts/scan_solo/ai_agent_configs_spec.rb` — persistência e 5 rejeições.
- [x] T05 — Slots de template CT-09 e cabeçalho de documento
      Arquivos: `app/models/scan_solo/template_mapping.rb`, `app/services/scan_solo/messaging/template_resolver.rb`, `app/services/scan_solo/messaging/template_availability_report.rb`, `app/controllers/api/v1/accounts/scan_solo/cadence_templates_controller.rb`, `spec/models/scan_solo/template_mapping_spec.rb`, `spec/services/scan_solo/messaging/template_resolver_spec.rb`, `spec/requests/api/v1/accounts/scan_solo/cadence_templates_spec.rb`
      Mudança:
        • `SINGLE_TEMPLATES` (`proposta_enviada`, `lead_manual_inicial`, `proposta_acompanhamento` → convenções), com `step` nulo só para slots.
        • `TemplateResolver.call(..., document:)` gera `processed_params['header']` (`media_url`, `media_type: document`, `media_name`).
        • O relatório ganha as linhas de slot e o controller aceita `step: null` nos slots.
      Cobre: CT-09, RF-07, RF-29, RF-31
      Acceptance criteria: `lead_manual_inicial` sem mapeamento → `scansolo_lead_manual_inicial`, com mapeamento → nome mapeado; `document:` → header com os 3 campos; sem `document:` → `processed_params` igual ao de hoje; `GET cadence_templates` inclui 3 linhas de slot; `PUT proposta_acompanhamento` com `step: null` → 200; `lead_manual_inicial` com step → inválido.
      Testes: os 3 specs listados — resolução, header, validação e endpoint.
- [x] T06 — Textos backend (`en.yml`)
      Arquivos: `config/locales/en.yml`, `spec/lib/scansolo_locale_spec.rb` (novo)
      Mudança: seção `en.scan_solo` com assunto/seções/instruções do e-mail de orçamento, bloco CT-04 (delimitadores + 5 rótulos), correção, aviso do RF-53 com o texto exato ("Recebi todas as informações, obrigado! Nosso comercial já está preparando seu orçamento. Assim que estiver pronto, envio por aqui."), resposta padrão de negociação, e-mail de negociação e palavras do extenso.
      Cobre: RNF-08, CT-03, CT-04, RF-35, RF-53
      Acceptance criteria: `I18n.t('scan_solo.quote.block.labels')` = os 5 rótulos do CT-04 na ordem; `I18n.t('scan_solo.negotiation.standard_reply')` = "Vou verificar isso com nosso comercial. Só um momento."; `I18n.t('scan_solo.quote.customer_notice')` = texto exato do RF-53.
      Testes: `spec/lib/scansolo_locale_spec.rb` — rótulos e texto padrão.

## Phase 3: Origem do lead, serviço de cadastro manual e valor por extenso

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos

- [x] T07 — Valor por extenso determinístico (`AmountInWords`)
      Arquivos: `app/services/scan_solo/quote/amount_in_words.rb` (novo), `spec/services/scan_solo/quote/amount_in_words_spec.rb` (novo)
      Mudança: função pura pt-BR (reais/centavos, até 999.999.999,99, `ArgumentError` para ≤ 0), com palavras de `scan_solo.amount_in_words.*`.
      Cobre: RF-47, CT-05
      Acceptance criteria: `12500.00` → "doze mil e quinhentos reais"; `1.00` → "um real"; `1000.00` → "mil reais"; `1234567.89` → "um milhão, duzentos e trinta e quatro mil, quinhentos e sessenta e sete reais e oitenta e nove centavos"; `0.50` → "cinquenta centavos"; `0` → `ArgumentError`.
      Testes: `spec/services/scan_solo/quote/amount_in_words_spec.rb` — tabela acima.
- [x] T08 — Origem do lead: classificador, bootstrap e backfill
      Arquivos: `app/services/scan_solo/pipeline/lead_source_classifier.rb` (novo), `app/services/scan_solo/pipeline/opportunity_bootstrap_service.rb`, `lib/tasks/scansolo.rake`, `spec/services/scan_solo/pipeline/lead_source_classifier_spec.rb` (novo), `spec/services/scan_solo/pipeline/opportunity_bootstrap_service_spec.rb`, `spec/lib/tasks/scansolo_rake_spec.rb`
      Mudança:
        • O classificador pega a 1ª mensagem não privada `incoming`/`outgoing` por `created_at`: `incoming` → `website`; `outgoing` de `User` → `manual`; senão nil.
        • O bootstrap grava `lead_source` no bloco do `create_or_find_by!` e no payload da auditoria.
        • Rake `scansolo:backfill_lead_source` com `update_columns` só quando o resultado não é nulo.
      Cobre: RF-01, RF-02, RF-03
      Acceptance criteria: os 3 casos do RF-02 e os 4 do RF-03 corretos; nota privada/`activity` ignoradas; 2ª execução do backfill → 0 alterações; contagens de `PipelineStageEvent`/`CadenceEnrollment`/`LeadStateEvent` e `updated_at` inalterados; `website` × `manual` em `em_contato` → mesma `CadenceDefinition` e mesmos `scheduled_at` relativos.
      Testes: os 3 specs listados — classificação, bootstrap e backfill idempotente.
- [x] T09 — `ManualLeadService` (cadastro "Novo lead")
      Arquivos: `app/services/scan_solo/pipeline/manual_lead_service.rb` (novo), `lib/custom_exceptions/scan_solo.rb`, `spec/services/scan_solo/pipeline/manual_lead_service_spec.rb` (novo)
      Mudança: numa transação, nesta ordem:
        1. `pg_advisory_xact_lock` por conta+telefone;
        2. contato por telefone e depois por e-mail; conflito → `contact_conflict`; nenhum → `create!` com `custom_attributes['empresa']`;
        3. opt-out → `contact_opted_out`;
        4. oportunidade não terminal → `opportunity_exists` com id;
        5. conversa aberta sem oportunidade no inbox → reusa; senão `ContactInboxBuilder` + `ConversationBuilder`, com `assignee_id` = owner;
        6. `PipelineOpportunity.create!(novo_lead, manual, owner_id, last_customer_interaction_at: nil)`;
        7. auditoria `pipeline.opportunity_created` `source: manual`;
        8. `StageEntryEnroller` + passo 1 `skipped` (`manual_initial_template`) via `AttemptEvidenceRecorder`.
        • Exceção `CustomExceptions::ScanSolo::ManualLeadRejected(code, opportunity_id)`.
      Cobre: RF-04, RF-05, RF-06, RF-09, RF-10, RF-11, RF-46
      Acceptance criteria:
        • telefone ou e-mail existente → 0 contatos novos; nenhum → 1; 2 threads mesmo telefone → 1 contato;
        • conflito/opt-out/oportunidade aberta → exceção com o código e contagens inalteradas; única oportunidade `perdido` → cria;
        • conversa aberta sem oportunidade → 0 conversas novas; falha no `create!` da oportunidade → 0 contatos/conversas novos;
        • passo 1 `skipped` sem `message_id`, passos 2–4 em T+24/48/96 h e 0 mensagens em T+2 h;
        • 1 `LeadState` `em_andamento` e 1 auditoria.
      Testes: `spec/services/scan_solo/pipeline/manual_lead_service_spec.rb` — os casos acima com relógio congelado.

## Phase 4: Template inicial do lead manual e leitura CT-02

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-operacao-centralizada/openapi.yaml` — `PipelineOpportunity`, `PipelineOpportunityDetail`, `Proposal`, `ProposalVersion`
4. `.spec/features/scansolo-operacao-centralizada/asyncapi.yaml` — `nativeMessageUpdated` (`manual_lead`)

- [x] T10 — Template inicial do lead manual e falha visível (RF-07, RF-08)
      Arquivos: `app/services/scan_solo/pipeline/manual_lead_outreach.rb` (novo), `app/services/scan_solo/pipeline/manual_lead_service.rb`, `app/services/scan_solo/conversation_listener.rb`, `app/services/scan_solo/messaging/delivery_reconciler.rb`, `spec/services/scan_solo/pipeline/manual_lead_outreach_spec.rb` (novo), `spec/services/scan_solo/messaging/delivery_reconciler_spec.rb`
      Mudança:
        • `ManualLeadOutreach`: resolve o slot `lead_manual_inicial` + guard; bloqueado → auditoria `pipeline.manual_lead_template_blocked`; senão `NativeTemplateSender` com origem `manual_lead`.
        • `ManualLeadService` chama o outreach via `after_all_transactions_commit`.
        • `TEMPLATE_ORIGINS` += `manual_lead`.
        • O reconciliador audita `pipeline.manual_lead_template_failed` com `external_error`, 1 vez por mensagem.
      Cobre: RF-07, RF-08, RNF-01
      Acceptance criteria: 1 `Message` de template com `scansolo_origin: 'manual_lead'` e o nome mapeado; 0 HTTP direto; `ai_control_state` `ai_active`; guard bloqueado → 0 mensagens + 1 auditoria com `reason`; mensagem `failed` → 1 auditoria com `external_error`, sem duplicar em novo update; `transaction_open?` falso no envio.
      Testes: `manual_lead_outreach_spec.rb`, `delivery_reconciler_spec.rb` — envio, bloqueio, falha e RNF-01.
- [x] T11 — Leitura CT-02 (index/show/proposals) com queries constantes
      Arquivos: `app/controllers/api/v1/accounts/scan_solo/pipeline_opportunities_controller.rb`, `app/views/api/v1/accounts/scan_solo/pipeline_opportunities/_pipeline_opportunity.json.jbuilder`, `app/views/api/v1/accounts/scan_solo/pipeline_opportunities/show.json.jbuilder`, `app/views/api/v1/accounts/scan_solo/pipeline_opportunities/index.json.jbuilder`, `app/views/api/v1/accounts/scan_solo/proposals/_proposal.json.jbuilder`, `app/views/api/v1/accounts/scan_solo/proposals/_proposal_version.json.jbuilder`, `app/controllers/api/v1/accounts/scan_solo/proposals_controller.rb`, `spec/requests/api/v1/accounts/scan_solo/pipeline_opportunities_centralized_spec.rb` (novo), `spec/requests/api/v1/accounts/scan_solo/proposals_spec.rb`
      Mudança:
        • `index` com `includes` (contato, eventos, estado, solicitação, extensão, proposta atual) e `next_follow_up_at` agrupado numa query; `stage_history` ordenado em Ruby.
        • Novos `lead_source`, `company`/`service`/`city_uf` (valor ≠ faltante), `ai_control_state` (default `ai_active`), `quote_request_status`, `proposal_status`.
        • `show` com `quote_request`, `proposal` e `initial_template_failure { reason, status (blocked|failed), occurred_at }` (da auditoria). `quote_request_resend_available` fica para T40.
        • Proposals com `proposal_number`, `valid_until`, `document_url` e `quote_request_status`.
      Cobre: CT-02, RF-01, RF-33, RNF-06, RNF-10, UI-02, UI-04, UI-05
      Acceptance criteria: mesma contagem de `sql.active_record` no `index` com 5 e 50 oportunidades; cada campo novo correto; `show` com os 3 objetos; guard bloqueado → `initial_template_failure.status` = `blocked` com o `reason`; mensagem `failed` → `status: failed` com o `external_error`; sem falha → `null`; fixtures legadas sem erro; `pipeline_opportunities_spec.rb` verde sem alteração; `pipeline_opportunities_lead_state_spec.rb` verde com a asserção `eq` das chaves do `show` atualizada para a lista exata e ordenada do CT-02 (expectativa alterada pelo CT-02, conforme RNF-11).
      Testes: `pipeline_opportunities_centralized_spec.rb`, `proposals_spec.rb` — campos, queries e legado.

## Phase 5: Endpoint "Novo lead" e interrupção da cadência

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-operacao-centralizada/openapi.yaml` — `createPipelineOpportunity` (CT-01)
4. `.spec/features/scansolo-operacao-centralizada/asyncapi.yaml` — `nativeMessageCreated` (RF-43)

- [x] T12 — Endpoint `POST /pipeline_opportunities` (CT-01)
      Arquivos: `config/routes.rb`, `app/controllers/api/v1/accounts/scan_solo/pipeline_opportunities_controller.rb`, `app/policies/scan_solo/pipeline_opportunity_policy.rb`, `app/views/api/v1/accounts/scan_solo/pipeline_opportunities/create.json.jbuilder` (novo), `spec/requests/api/v1/accounts/scan_solo/pipeline_opportunities_create_spec.rb` (novo)
      Mudança:
        • Rota `create`; `create?` = `account_user.present?`.
        • Borda 422: `missing_name`, `invalid_phone` (regex E.164 do `Contact`), `invalid_email`, `invalid_owner`, `invalid_inbox` (WhatsApp na allowlist publicada; omitido só com exatamente 1).
        • `ManualLeadRejected` → 422 com código e `opportunity_id`.
        • 201 com show + `contact_created`.
      Cobre: CT-01, RF-05, RF-09, UI-01
      Acceptance criteria: as 7 condições do RF-05 → 422 com o código e contagens de `Contact`/`Conversation`/`PipelineOpportunity`/`Message` inalteradas; `opportunity_exists` → 422 com `opportunity_id`; 201 com `lead_source: manual`, `stage: novo_lead`, `contact_created` e `lead_state`; 404 com o flag desligado; regra do inbox único/múltiplo.
      Testes: `pipeline_opportunities_create_spec.rb` — 422s, 201 e 404.
- [x] T13 — Interrupção da tentativa pendente a cada resposta (RF-43)
      Arquivos: `app/services/scan_solo/cadence/reply_interruption_service.rb` (novo), `app/services/scan_solo/conversation_listener.rb`, `app/services/scan_solo/cadence/reply_completeness_detector.rb`, `app/services/scan_solo/ai_turn/turn_orchestrator.rb` (só comentário), `spec/services/scan_solo/cadence/reply_interruption_service_spec.rb` (novo), `spec/services/scan_solo/cadence/reply_completeness_detector_spec.rb`, `spec/services/scan_solo/conversation_listener_spec.rb`
      Mudança:
        • Serviço com `enrollment.with_lock`: ciclo = última `outgoing` não privada antes da mensagem.
        • Já houve auditoria `cadence.attempt_interrupted_by_reply` depois disso → nada; senão cancela a próxima `scheduled` via `AttemptEvidenceRecorder` + 1 auditoria `{enrollment_id, attempt_id, message_id}`.
        • Chamado no listener (ramo não-criado, depois da regra de entrada).
        • O detector perde o ramo parcial (só "completa → cancela tudo").
      Cobre: RF-43, RF-44
      Acceptance criteria: parcial → próxima `cancelled` + 1 auditoria mesmo com turno `superseded`/`failed`; rajada de 3 sem saída → 1 cancelamento, demais `scheduled_at` intactos, `sent` intactas; cliente → saída → cliente → 2; matrícula posterior à mensagem → 0; detector parcial → 0 cancelamentos (expectativa alterada pelo RF-43, citada conforme RNF-11); `git diff 8a168c0590 -- db/seeds/scansolo_cadence_definitions.rb` vazio.
      Testes: `reply_interruption_service_spec.rb`, `reply_completeness_detector_spec.rb`, `conversation_listener_spec.rb` — ciclos e independência do turno.

## Phase 6: E-mail nativo — composição, caixa de orçamento e leitura do bloco

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-operacao-centralizada/asyncapi.yaml` — `quoteRequestEmail` (CT-03), `quoteReplyEmail` (CT-04), `ParsedQuoteBlock`

- [x] T14 — Composição dos e-mails (CT-03): solicitação, correção e negociação
      Arquivos: `app/services/scan_solo/quote/email_composer.rb` (novo), `spec/services/scan_solo/quote/email_composer_spec.rb` (novo)
      Mudança:
        • Puro; devolve `Email(subject, text, html)`, com HTML em `<br>` e valores escapados.
        • `.request(opportunity:, projection:)`: identificação (inclui o link `/app/accounts/<id>/conversations/<display_id>`), campos ≠ faltante com "(a confirmar)" nos inferidos e bloco vazio CT-04.
        • `.correction(problems:)` e `.negotiation(payload:)` (9 itens).
        • Textos do `en.yml`.
      Cobre: CT-03, RF-13, RF-18, RF-37, RNF-07, RNF-08
      Acceptance criteria: `request` contém id, rótulos e valores `confirmado`/`inferido`, "(a confirmar)" só nos inferidos e as 5 linhas de rótulo entre delimitadores; sem valor `faltante` nem `api_access_token`; `<br>` entre campos; `correction([:payment_terms])` contém "Condições de pagamento" e o bloco; `negotiation` contém os 9 itens e o link.
      Testes: `spec/services/scan_solo/quote/email_composer_spec.rb` — 3 composições.
- [x] T15 — Caixa de orçamento e thread de e-mail nativa
      Arquivos: `app/services/scan_solo/quote/mailbox.rb` (novo), `app/services/scan_solo/quote/email_thread.rb` (novo), `lib/custom_exceptions/scan_solo.rb`, `spec/services/scan_solo/quote/mailbox_spec.rb` (novo), `spec/services/scan_solo/quote/email_thread_spec.rb` (novo)
      Mudança:
        • sem destinatário fixo no código; `.resolve!(account)` devolve `Settings(inbox, recipient)` da config publicada (`quote_inbox_id`, `quote_recipient_email`) ou levanta `QuoteInboxMisconfigured` (`quote_inbox_missing|quote_inbox_not_email|quote_inbox_allowlisted`).
        • `EmailThread.open!(inbox:, recipient:, subject:, marker:)`: `ContactInboxWithContactBuilder` + `ConversationBuilder` com `mail_subject` e `scansolo_thread`.
        • `EmailThread.post!(conversation:, recipient:, email:)`: só fora de transação; `messages.create!` outgoing com `to_emails` e `email.html_content.reply`.
      Cobre: CT-03, RF-12, RF-14, RF-16, RF-37, RF-42, RNF-01, RNF-04
      Acceptance criteria: as 3 condições → exceção com o `reason`; destinatário alterado só no rascunho → `Settings` usa o publicado; `post!` → 1 e-mail (ActionMailer `:test`) com From = e-mail do canal, To = `[destinatário publicado]`, Subject = `mail_subject` e HTML com `<br>`; 2º `open!` reusa o contato; `post!` com `transaction_open?` falso.
      Testes: `mailbox_spec.rb`, `email_thread_spec.rb` — configuração e envio nativo.
- [x] T16 — Leitura determinística do bloco (CT-04)
      Arquivos: `app/services/scan_solo/quote/response_block_parser.rb` (novo), `spec/services/scan_solo/quote/response_block_parser_spec.rb` (novo)
      Mudança:
        • Puro, sem LLM.
        • Pré-processamento: ignora linhas `>`, normaliza caixa/acentos/espaços/marcadores; rótulos do `en.yml`; delimitadores opcionais; HTML convertido quando o texto é vazio.
        • Bloco: o 1º com ≥ 1 rótulo preenchido; cada valor até o próximo rótulo, o FIM ou a citação.
        • Valor pela gramática CT-04 (> 0); `problems` para obrigatórios vazios ou ilegíveis.
      Cobre: CT-04, RF-17, RF-18, RF-21
      Acceptance criteria: resposta no topo + citação vazia → 4 campos aparados e `R$ 12.500,00` → `12500.00`; variações toleradas dão os mesmos valores; escopo multilinha preservado; `12500.00` e `0,00` → `[:total_value]`; sem "Condições de pagamento" → `[:payment_terms]`; só citação → 4 problemas; só HTML → mesmos valores; 0 chamadas a `ModelInvoker`/`RubyLLM`.
      Testes: `spec/services/scan_solo/quote/response_block_parser_spec.rb` — tabela de variações.

## Phase 7: GATE HUMANO — HG-A, HG-B e HG-C (inbox de e-mail, config publicada, templates Meta)

> NÃO executada pelo `ralph.sh`: fase de operador/humano (configuração da instância Chatwoot e templates Meta). Os checkboxes ficam para registro: só marcar `[x]` com a evidência descrita. Concluir antes do deploy da Phase 8.

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-operacao-centralizada/openapi.yaml` — `updateAiAgentConfigDraft`, `upsertCadenceTemplate`

- [ ] T17 — GATE HUMANO HG-A/HG-C: inbox de e-mail e configuração publicada
      Arquivos: nenhum arquivo de código (operacional na instância Chatwoot de produção)
      Mudança: tarefa humana, não executável pelo agente.
        1. Criar o inbox de e-mail `atendimento.comercial@scansolo.com.br` (IMAP + SMTP), sem bot.
        2. `PUT /scan_solo/ai_agent_config/draft` com `quote_inbox_id`, opcional `commercial_user_id` (Luciano) e `quote_recipient_email` só se for diferente do valor inicial; depois `POST .../publish`.
        3. Confirmar o inbox fora da allowlist.
        • Concluir antes do deploy da Phase 8.
      Cobre: HG-A, HG-C, RF-54, RF-16
      Acceptance criteria: `rails runner` sobre a config publicada imprime `["Channel::Email", false, <id ou nil>, "<destinatário>"]` (tipo do inbox de orçamento, presença na allowlist, usuário comercial, destinatário publicado); um e-mail de teste ao inbox vira conversa em ≤ 1 min.
      Testes: comando `rails runner` do PLAN T17 — evidência registrada no deploy.
- [ ] T18 — GATE HUMANO HG-B: templates Meta e mapeamento
      Arquivos: nenhum arquivo de código (Meta WhatsApp Business + tela de Templates)
      Mudança: tarefa humana, não executável pelo agente.
        1. Definir os textos e submeter os 3 templates: abordagem inicial; proposta com cabeçalho `DOCUMENT`; acompanhamento.
        2. Depois de aprovados e sincronizados, mapear os slots `lead_manual_inicial`, `proposta_enviada` (step nulo) e `proposta_acompanhamento`.
        • Não bloqueia as Phases 8–15 (o guard bloqueia e audita); bloqueia a ativação da Phase 18 (T39).
      Cobre: HG-B, CT-09
      Acceptance criteria: `GET /scan_solo/cadence_templates` mostra as 3 linhas de slot com `availability: "available"` e `mapped: true`.
      Testes: chamada `GET` acima — evidência registrada.

## Phase 8: Solicitação de orçamento e geração com dados comerciais

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-operacao-centralizada/asyncapi.yaml` — `quoteRequestEmail` (CT-03), `MakeIntegrationRequestPayload`/`Commercial` (CT-05)
4. `.spec/features/scansolo-operacao-centralizada/openapi.yaml` — `generateProposal` (RF-25)

- [x] T19 — Solicitação de orçamento na conclusão + aviso único ao cliente
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
- [x] T20 — Geração com dados comerciais (CT-05) e IA sem `proposal_generate`
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

- [x] T21 — Processamento da resposta do Luciano e roteamento no listener
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
- [x] T22 — Publicador de notificação (CT-07) e adaptador de e-mail
      Arquivos: `app/services/scan_solo/notifications/publisher.rb` (novo), `app/services/scan_solo/notifications/email_adapter.rb` (novo), `app/services/scan_solo/notifications/negotiation_payload.rb` (novo), `spec/services/scan_solo/notifications/publisher_spec.rb` (novo), `spec/services/scan_solo/notifications/email_adapter_spec.rb` (novo), `spec/services/scan_solo/notifications/negotiation_payload_spec.rb` (novo)
      Mudança:
        • `NegotiationPayload.build` monta exatamente o CT-07.
        • `Publisher.call(event:, payload:, adapters: ADAPTERS)`: falha ou exceção → auditoria `negotiation.notification_failed` + exceção capturada, sem propagar; sucesso → `negotiation.notification_sent`.
        • `EmailAdapter`: destinatário publicado (`Mailbox.resolve!`), thread própria com marcador `negotiation_notification` + `EmailComposer.negotiation`; inbox mal configurado → `success: false`.
      Cobre: CT-07, RF-37, RF-39, RF-41, RF-42
      Acceptance criteria: payload com chaves e tipos do CT-07 (`proposal`/`current_value` nulos sem proposta, ≤ 3 mensagens); adaptador de teste recebe payload idêntico; adaptador que levanta → 1 auditoria + 1 exceção, sem propagar; e-mail com os 9 itens e o link; inbox ausente → falha registrada.
      Testes: os 3 specs listados — payload, publicador e adaptador.
- [x] T40 — Reenvio manual auditado e idempotente da solicitação de orçamento (RF-56, CT-12)
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

- [x] T23 — API de pendentes de vínculo (CT-08)
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
- [x] T24 — Entrega da proposta pelo WhatsApp com PDF e reenvio sem Make (RF-29, RF-32, CT-10)
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
- [x] T25 — Aceite real, falha posterior e acompanhamento (RF-30, RF-31)
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

- [x] T26 — Negociação: sinal, resposta padrão, etapa, handoff, notificação e atribuição (RF-35..RF-40)
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

- [x] T27 — Frontend base: textos, API e stores
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

- [x] T28 — Kanban: card enxuto, navegação e formulário "Novo lead" (UI-01, UI-02, UI-03)
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/KanbanBoard.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/NewLeadDialog.vue` (novo), `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/specs/KanbanBoard.spec.js`, `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/specs/NewLeadDialog.spec.js` (novo)
      Mudança:
        • Botão "Novo lead" no cabeçalho.
        • Card com origem, empresa ou contato, serviço, cidade/UF, "Sem interação há X dias" (X ≥ 1), status comercial e indicador humano.
        • Clique → detalhe (arrasto preservado).
        • `NewLeadDialog` (`components-next/`): validação E.164 local, inbox pré-selecionado com 1 inbox WhatsApp allowlisted, erros 422 por código e "Abrir oportunidade existente".
      Cobre: UI-01, UI-02, UI-03, RF-33
      Acceptance criteria: sem telefone → erro e 0 requisições; `contact_conflict` → mensagem i18n; `opportunity_exists` com `opportunity_id: 7` → `router.push` ao detalhe 7; 201 → card `novo_lead` com "COMERCIAL"; card sem empresa mostra o contato; −49 h → "Sem interação há 2 dias"; `awaiting_human` mostra o indicador e `ai_active` oculta; clique → `router.push` com `opportunityId`; arrasto igual; menu idêntico.
      Testes: `KanbanBoard.spec.js`, `NewLeadDialog.spec.js` — componente.
- [x] T29 — Tela do lead (`OpportunityDetail`, UI-04, UI-07)
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/OpportunityDetail.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/specs/OpportunityDetail.spec.js`
      Mudança: origem, responsável, seções "Coletado"/"A confirmar"/"Faltante" a partir de `leadState.blocks`, status do orçamento (datas), status da proposta (versão, número, status, valor/validade quando `generated`/`sent`, link `documentUrl`) falha do template inicial com motivo e status (oculta quando `null`) e a ação UI-07 "Reenviar solicitação de orçamento" (só admin via `useScanSoloRole` e com `quoteRequestResendAvailable`), com sucesso/erro 422 por código e recarga do `show`.
      Cobre: UI-04, UI-07, RF-45, RF-08, RF-56
      Acceptance criteria: fixture do `show` → as 3 seções com os campos certos; origem, orçamento e proposta exibidos; `initialTemplateFailure` → motivo e status visíveis, `null` → oculto; admin com `quoteRequestResendAvailable: true` → ação visível e clique → POST do CT-12 + sucesso; não admin ou `false` → oculta; 422 `quote_request_closed` → mensagem i18n; textos só do i18n.
      Testes: `OpportunityDetail.spec.js` — componente.
- [x] T30 — Tela de Propostas: pendentes de vínculo e desativação de Aprovar/Enviar (UI-05, UI-06, RF-55 Etapa 1)
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/proposals/Proposals.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/proposals/QuoteRepliesPending.vue` (novo), `app/javascript/dashboard/routes/dashboard/scansolo/proposals/specs/Proposals.spec.js`, `app/javascript/dashboard/routes/dashboard/scansolo/proposals/specs/QuoteRepliesPending.spec.js` (novo)
      Mudança:
        • Seção de pendentes: "Vincular" para `unmatched`, com escolha de solicitação aberta; "Descartar" + solicitação de origem para `late_reply`.
        • Deixa de exibir Aprovar/Enviar e de chamá-los na tela; store e API legados ficam intactos (RF-55 Etapa 1).
        • Mostra o status da solicitação, número, validade e link do PDF; "Reenviar" só em `failed`; histórico só leitura.
      Cobre: UI-05, UI-06, RF-55 (Etapa 1), RF-19, RF-20, RF-23
      Acceptance criteria: 2 pendentes → 2 linhas; "Vincular" → POST com ids certos e a linha some; vazio → estado vazio; `late_reply` → origem + "Descartar" → POST `discard` e some; versões `generated`/`approved`/`sent` → 0 botões Aprovar/Enviar e status exibidos; `failed` → "Reenviar"; `grep -n "approveProposal\|sendProposal" routes/dashboard/scansolo` vazio; testes de clique em aprovar/enviar trocados pela ausência dos botões, citando RF-55/UI-06 (RNF-11).
      Testes: `Proposals.spec.js`, `QuoteRepliesPending.spec.js` — componente.
- [x] T31 — Configuração e Templates: 3 campos, sem toggle, rótulos dos slots (RF-54, UI-06)
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

- [x] T33 — Provas ponta a ponta e RNF transversais
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
- [x] T34 — Documentação de arquitetura e contratos
      Arquivos: `docs/agents/domain_rules.md`, `docs/agents/architecture.md`, `docs/agents/data_model.md`, `docs/agents/api_contracts.md`
      Mudança: atualizar só as seções citadas no PLAN (pipeline, cadência, proposta, guardrails, registry, handoff, "Quote request" com reenvio RF-56, fluxos, tabelas, endpoints com CT-12 e CT-11 desativado) com ponteiros para `openapi.yaml`/`asyncapi.yaml` desta feature.
      Cobre: CT-01, CT-02, CT-03, CT-04, CT-05, CT-06, CT-07, CT-08, CT-09, CT-10, CT-11, CT-12
      Acceptance criteria: `docs/agents/api_contracts.md` aponta para os 2 contratos; `domain_rules.md` descreve a interrupção ≤ 1 por ciclo, a solicitação de orçamento approve/send desativados (não removidos) e o reenvio manual; `approve`/`proposal.send` só em contexto histórico.
      Testes: `grep -n "scansolo-operacao-centralizada" docs/agents/api_contracts.md` com 2 ou mais linhas.

## Phase 15: Gates de qualidade

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos

- [x] T35 — Gates de qualidade e regressão
      Arquivos: nenhum arquivo novo (corrige só quebras residuais nos arquivos já alterados)
      Mudança:
        • rubocop nos `.rb` alterados; `pnpm eslint` com os `.js`/`.vue` explícitos; `pnpm test` nos specs tocados; `./scripts/ralph-test.sh`.
        • Checagens RNF-05: `git diff 8a168c0590 --stat -- app/services/scan_solo/ai_turn/` restrito a `attempt_runner.rb`, `prompt_builder.rb` e `input_guardrail.rb`, mais `turn_orchestrator.rb` só com comentário (autorizado no T13); `output_validator.rb` sem diff.
        • RNF-10/RF-44: sem `remove_*`, seeds de cadência intactos (`git diff 8a168c0590 -- db/seeds/scansolo_cadence_definitions.rb` vazio), 6 estados de controle.
        • RNF-11: `git diff 8a168c0590 -- spec app/javascript` sem `skip`/`pending`/`xit`/`it.skip` novos; cada spec existente alterado citado numa task com o requisito.
        • RF-55 Etapa 1: nenhuma tela chama `approveProposal`/`sendProposal`; rotas `approve`/`send` ainda presentes.
        • RNF-07 (sem segredos literais) e enterprise (0 referências).
      Cobre: RNF-04, RNF-05, RNF-07, RNF-08, RNF-10, RNF-11, RF-44, RF-46, RF-55
      Acceptance criteria: rubocop 0 offenses; eslint 0 erros; `./scripts/ralph-test.sh` exit 0; os greps de RNF-05/RNF-07/RNF-10/RNF-11/RF-44/RF-55/enterprise retornam o esperado no PLAN.
      Testes: comandos acima.

## Phase 16: GATE HUMANO HG-D — backup dos blueprints Make e aprovação

> NÃO executada pelo `ralph.sh`: fase de operador/humano (exportação de blueprints no Make via MCP e aprovação do desenvolvedor). Os checkboxes ficam para registro: só marcar `[x]` com a evidência descrita.

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T36 — GATE HUMANO HG-D: backup dos blueprints Make e aprovação
      Arquivos: `.spec/features/scansolo-operacao-centralizada/make/backups/<scenarioId>-<AAAAMMDD>.json` (6 novos), `.spec/features/scansolo-operacao-centralizada/make/REGISTRO.md` (novo)
      Mudança: tarefa humana, não executável pelo agente. Nenhuma alteração de cenário nesta task.
        1. Exportar via Make MCP (team 701134, pasta `scanSolo`) os blueprints de `ScanSOLO_Proposta_Entrada`, 6177829, 6036802, 6019491, 5497443 e 6177833.
        2. Conferir que não há segredo literal.
        3. Registrar no `REGISTRO.md` as exportações e a aprovação explícita do desenvolvedor para T37 e T38.
      Cobre: RF-51, RNF-07, HG-D
      Acceptance criteria: 6 arquivos `.json` em `make/backups/`; grep de segredos literais vazio; `REGISTRO.md` com a aprovação datada do desenvolvedor para T37 e T38.
      Testes: `ls .spec/features/scansolo-operacao-centralizada/make/backups/*.json | wc -l` → 6.

## Phase 17: Make — legados desativados e `Entrada` adaptada (inativa)

> NÃO executada pelo `ralph.sh`: fase de operador/humano (alterações no Make via MCP, só com o backup e a aprovação registrados na Phase 16). Os checkboxes ficam para registro: só marcar `[x]` com a evidência descrita.

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-operacao-centralizada/asyncapi.yaml` — CT-05 (payload e exemplo `generateWithCommercial`) e CT-06 (`ProposalGeneratedResult`, `ProposalFailureResult`)

- [ ] T37 — Make: desativar os cenários legados (RF-51)
      Arquivos: `.spec/features/scansolo-operacao-centralizada/make/REGISTRO.md`
      Mudança: com o backup e a aprovação de T36, desativar (nunca apagar) 6177829, 6036802, 6019491, 5497443 e 6177833 e registrar data e estado anterior.
      Cobre: RF-51, RNF-07, RNF-10
      Acceptance criteria: a listagem do Make mostra os 5 com `isActive: false`; `REGISTRO.md` com 5 linhas de desativação.
      Testes: listagem de cenários via Make MCP.
- [ ] T38 — Make: adaptar a `Entrada` ao CT-05/CT-06 (inativa)
      Arquivos: `.spec/features/scansolo-operacao-centralizada/make/REGISTRO.md`
      Mudança: com o backup e a aprovação de T36, e mantendo o cenário inativo:
        • RF-47: template com `proposal_number`, `commercial.*` (inclui `total_value_in_words`, usado como recebido, sem recalcular) e `qualification.projeto`; sem e-mail/Form ao comercial e sem envio ao cliente.
        • RF-48: PDF no Drive e callback `success` com `artifact_url` de download direto, `total_value` igual e `valid_until` por `validade_dias`.
        • RF-49: error handlers com callback `failure` assinado via "Create JSON".
        • RF-50: idempotência por `pv_{id}`.
        • Segredos só do data store; "Run once" com o exemplo do `asyncapi.yaml`.
      Cobre: RF-47, RF-48, RF-49, RF-50, CT-05, CT-06, RNF-07
      Acceptance criteria: documento com número, 4 textos, valor e extenso; 0 e-mails pelo Make; falha forçada de cada módulo → JSON válido com `"`, `\` e quebra de linha; 2 execuções do mesmo `pv_` → 1 documento e o mesmo `artifact_url`; cenário `isActive: false`; execuções registradas.
      Testes: execuções "Run once" registradas no `REGISTRO.md`.

## Phase 18: GATE HUMANO HG-03 — ativação da `Entrada` e smoke em produção

> NÃO executada pelo `ralph.sh`: fase de operador/humano (confirmação HG-03 pelo desenvolvedor, ativação no Make via MCP e smoke em produção). Os checkboxes ficam para registro: só marcar `[x]` com a evidência descrita.

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-operacao-centralizada/asyncapi.yaml` — CT-05/CT-06

- [ ] T39 — GATE HUMANO HG-03: credenciais, ativação da `Entrada` e smoke em produção (RF-52, RF-48)
      Arquivos: `.spec/features/scansolo-operacao-centralizada/make/REGISTRO.md`
      Mudança: tarefa humana com evidência, nesta ordem:
        1. HG-03: comparar por fingerprint SHA-256 (nunca pelo valor) `scan_solo.make.{scenario_url, secret, inbound_signing_secret}` com o `ScanSOLO_Config`.
        2. Conferir HG-A e HG-B concluídas e as Phases 1–15 em produção.
        3. Ativar a `Entrada`.
        4. Smoke com contato de teste: lead manual → e-mail → resposta → geração → `curl -sI <artifact_url>` (200, `application/pdf`) → template com PDF → `proposta_enviada` → acompanhamento.
      Cobre: RF-52, RF-48, HG-03, RNF-07
      Acceptance criteria: `REGISTRO.md` com a confirmação HG-03 datada antes do horário de ativação; `Entrada` ativa na listagem; evidência do `curl` e do `GET /pipeline_opportunities/:id` do smoke.
      Testes: smoke registrado no `REGISTRO.md`.

## Phase 19: GATE HUMANO — verificação de não uso do aprovar/enviar legado (RF-55 Etapa 2)

> NÃO executada pelo `ralph.sh`: fase de operador/humano (evidência de código, blueprints Make e produção). Os checkboxes ficam para registro: só marcar `[x]` com o registro preenchido.

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-operacao-centralizada/openapi.yaml` — `x-deactivated-paths` (CT-11)

- [ ] T41 — GATE HUMANO: verificação de não uso do aprovar/enviar legado (RF-55 Etapa 2)
      Arquivos: `.spec/features/scansolo-operacao-centralizada/make/REGISTRO-LEGADO.md` (novo)
      Mudança: tarefa de operador com evidência, não executada pelo `ralph.sh`. Registrar com data e comando/consulta:
        1. frontend: `grep -rn "approveProposal\|sendProposal" app/javascript` sem chamador;
        2. backend: `grep -rn "ApproveService\|SendService\|request_send\|proposal\.send" app lib config` sem chamador fora do próprio legado e do schema histórico;
        3. Make: busca de `/approve`, `/send` e `proposal.send` nos blueprints de `make/backups/` e nos cenários ativos;
        4. produção: auditorias `agent_action.proposal_approve|proposal_send`, `MakeRequest` `proposal.send` e logs de acesso a `approve`/`send` desde o deploy da Phase 13;
        5. conclusão "sem uso" ou "dependência encontrada: <qual>" (sem conclusão vale "dependência encontrada").
      Cobre: RF-55, CT-11, RNF-10
      Acceptance criteria: `REGISTRO-LEGADO.md` com os 4 itens, a conclusão e a data.
      Testes: revisão do registro pelo desenvolvedor.

## Phase 20: Remoção condicional do aprovar/enviar legado (RF-55 Etapa 2)

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-operacao-centralizada/openapi.yaml` — `x-deactivated-paths` (CT-11)
4. `.spec/features/scansolo-operacao-centralizada/make/REGISTRO-LEGADO.md` — conclusão da Phase 19 (sem "sem uso", esta fase termina sem mudança de código)

- [ ] T32 — Remoção condicional do aprovar/enviar legado (RF-55 Etapa 2, CT-11)
      Arquivos: só se `.spec/features/scansolo-operacao-centralizada/make/REGISTRO-LEGADO.md` (T41) concluir "sem uso": `config/routes.rb`, `app/controllers/api/v1/accounts/scan_solo/proposals_controller.rb`, `app/policies/scan_solo/proposal_policy.rb`, `app/services/scan_solo/proposal/approve_service.rb` (removido), `app/services/scan_solo/proposal/send_service.rb` (removido), `app/views/api/v1/accounts/scan_solo/proposals/approve.json.jbuilder` (removido), `app/views/api/v1/accounts/scan_solo/proposals/send_proposal.json.jbuilder` (removido), `app/services/scan_solo/proposal/make_provider.rb`, `app/services/scan_solo/proposal/mock_provider.rb`, `app/services/scan_solo/proposal/callback_handler.rb`, `app/javascript/dashboard/store/scansolo/proposals.js`, `app/javascript/dashboard/api/scansoloProposals.js`, `docs/agents/api_contracts.md`, `docs/agents/domain_rules.md`, `spec/services/scan_solo/proposal/approve_service_spec.rb` (removido), `spec/services/scan_solo/proposal/send_service_spec.rb` (removido), `spec/requests/api/v1/accounts/scan_solo/proposals_spec.rb`, `spec/services/scan_solo/proposal/make_provider_spec.rb`, `spec/services/scan_solo/proposal/mock_provider_spec.rb`, `spec/services/scan_solo/proposal/callback_handler_spec.rb`, `spec/integration/scan_solo/full_test_mode_spec.rb`
      Mudança:
        • Ler o `REGISTRO-LEGADO.md`. Conclusão "dependência encontrada" ou registro incompleto → não mudar nenhum arquivo, anotar no registro que o legado fica desativado e concluir a task.
        • Com "sem uso": remover rotas/actions `approve`/`send_proposal`, policies `approve?`/`send?`, `ApproveService`, `SendService`, `request_send` (Make e Mock), as 2 views e os métodos `approve`/`send` do store/API; `apply_send_result!` continua para callbacks históricos e chama `DeliveryService` no sucesso; docs passam CT-11 a "removido"; reexecutar os gates do T35.
        • Sempre preservados: coluna `require_proposal_approval`, enum `approved`, `approved_at`, `MakeCallback` históricos.
      Cobre: RF-55, CT-11, RNF-10, RNF-11
      Acceptance criteria: com "sem uso": `POST .../proposals/:id/approve` e `.../send` → 404, versão `approved` histórica → `GET` inalterado, callback `proposal.send` histórico aplicado sem erro, rubocop/eslint/`./scripts/ralph-test.sh` verdes; sem "sem uso": diff desta task vazio, rotas respondendo como antes e o registro apontando a dependência.
      Testes: `proposals_spec.rb` e specs listados (só no caso "sem uso").
