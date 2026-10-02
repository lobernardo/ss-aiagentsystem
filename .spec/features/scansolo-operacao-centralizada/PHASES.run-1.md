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

## Phase 1: Fundação de dados — migrações aditivas

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T01 — Migrações aditivas da feature
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

- [ ] T02 — Modelos `QuoteRequest`/`QuoteReply` e associações da oportunidade
      Arquivos: `app/models/scan_solo/quote_request.rb` (novo), `app/models/scan_solo/quote_reply.rb` (novo), `app/models/scan_solo/pipeline_opportunity.rb`, `spec/models/scan_solo/quote_request_spec.rb` (novo), `spec/models/scan_solo/quote_reply_spec.rb` (novo), `spec/models/scan_solo/pipeline_opportunity_spec.rb`
      Mudança:
        • `QuoteRequest`: enum `awaiting_reply/correction_requested/replied`, associações (`opportunity`, `account`, `email_conversation`, `reply_message`, `has_one :proposal_version`), `open?`.
        • `QuoteReply`: enums `kind` (`unmatched/late_reply`) e `status` (`pending/linked/discarded`).
        • `PipelineOpportunity`: `LEAD_SOURCES`, validação de `lead_source` (allow_nil), `has_one :quote_request` e `has_one :conversation_extension` (`primary_key`/`foreign_key: :conversation_id`).
      Cobre: RF-01, RF-15, RF-19, RF-22, RF-23, CT-02
      Acceptance criteria: 2ª solicitação na mesma oportunidade → `RecordNotUnique`; `message_id` duplicado em `QuoteReply` → `RecordNotUnique`; `lead_source: 'site'` inválido e `nil`/`website`/`manual` válidos; `opportunity.conversation_extension` resolve pela conversa.
      Testes: os 3 specs de modelo — unicidade, enums, validação e associação.
- [ ] T03 — `ProposalVersion`: número, validade, PDF e vínculo com a solicitação
      Arquivos: `app/models/scan_solo/proposal_version.rb`, `spec/models/scan_solo/proposal_version_spec.rb`
      Mudança: `has_one_attached :document`, `belongs_to :quote_request`/`:follow_up_message` (optional), `after_create` que grava `proposal_number = format('SS-%<year>d-%<id>06d', …)` e `document_url` (`rails_blob_url` com host `FRONTEND_URL`, ou nil).
      Cobre: RF-26, RF-29, CT-02, CT-09
      Acceptance criteria: 2 versões → 2 números distintos no formato `SS-AAAA-NNNNNN`; com PDF anexado, `document_url` começa com `FRONTEND_URL` e ≠ `artifact_url`; sem documento → nil.
      Testes: `spec/models/scan_solo/proposal_version_spec.rb` — número, `document_url`.
- [ ] T04 — Configuração RF-54 no backend (3 campos)
      Arquivos: `app/models/scan_solo/ai_agent_config.rb`, `app/controllers/api/v1/accounts/scan_solo/ai_agent_configs_controller.rb`, `app/views/api/v1/accounts/scan_solo/ai_agent_configs/_ai_agent_config.json.jbuilder`, `spec/requests/api/v1/accounts/scan_solo/ai_agent_configs_spec.rb`
      Mudança:
        • `FIELDS` ganha `quote_inbox_id`/`commercial_user_id`/`quote_recipient_email` (snapshot de publicação; fluxos leem só o publicado); `draft_params` permite os 3; `require_proposal_approval` continua aceito.
        • Borda 422: inbox não-e-mail, de outra conta ou na `allowed_inbox_ids` efetiva; usuário fora da conta; `allowed_inbox_ids` contendo o `quote_inbox_id`; destinatário vazio ou malformado.
        • jbuilder com as 3 chaves.
      Cobre: RF-54, RF-14, RF-16, RNF-05
      Acceptance criteria: salvar e publicar → os 3 valores em `draft` e `published`; cada condição inválida (inclusive destinatário vazio/malformado) → 422; destinatário editado só no rascunho não muda o publicado; exemplos existentes verdes.
      Testes: `spec/requests/api/v1/accounts/scan_solo/ai_agent_configs_spec.rb` — persistência e 5 rejeições.
- [ ] T05 — Slots de template CT-09 e cabeçalho de documento
      Arquivos: `app/models/scan_solo/template_mapping.rb`, `app/services/scan_solo/messaging/template_resolver.rb`, `app/services/scan_solo/messaging/template_availability_report.rb`, `app/controllers/api/v1/accounts/scan_solo/cadence_templates_controller.rb`, `spec/models/scan_solo/template_mapping_spec.rb`, `spec/services/scan_solo/messaging/template_resolver_spec.rb`, `spec/requests/api/v1/accounts/scan_solo/cadence_templates_spec.rb`
      Mudança:
        • `SINGLE_TEMPLATES` (`proposta_enviada`, `lead_manual_inicial`, `proposta_acompanhamento` → convenções), com `step` nulo só para slots.
        • `TemplateResolver.call(..., document:)` gera `processed_params['header']` (`media_url`, `media_type: document`, `media_name`).
        • O relatório ganha as linhas de slot e o controller aceita `step: null` nos slots.
      Cobre: CT-09, RF-07, RF-29, RF-31
      Acceptance criteria: `lead_manual_inicial` sem mapeamento → `scansolo_lead_manual_inicial`, com mapeamento → nome mapeado; `document:` → header com os 3 campos; sem `document:` → `processed_params` igual ao de hoje; `GET cadence_templates` inclui 3 linhas de slot; `PUT proposta_acompanhamento` com `step: null` → 200; `lead_manual_inicial` com step → inválido.
      Testes: os 3 specs listados — resolução, header, validação e endpoint.
- [ ] T06 — Textos backend (`en.yml`)
      Arquivos: `config/locales/en.yml`, `spec/lib/scansolo_locale_spec.rb` (novo)
      Mudança: seção `en.scan_solo` com assunto/seções/instruções do e-mail de orçamento, bloco CT-04 (delimitadores + 5 rótulos), correção, aviso do RF-53 com o texto exato ("Recebi todas as informações, obrigado! Nosso comercial já está preparando seu orçamento. Assim que estiver pronto, envio por aqui."), resposta padrão de negociação, e-mail de negociação e palavras do extenso.
      Cobre: RNF-08, CT-03, CT-04, RF-35, RF-53
      Acceptance criteria: `I18n.t('scan_solo.quote.block.labels')` = os 5 rótulos do CT-04 na ordem; `I18n.t('scan_solo.negotiation.standard_reply')` = "Vou verificar isso com nosso comercial. Só um momento."; `I18n.t('scan_solo.quote.customer_notice')` = texto exato do RF-53.
      Testes: `spec/lib/scansolo_locale_spec.rb` — rótulos e texto padrão.

## Phase 3: Origem do lead, serviço de cadastro manual e valor por extenso

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T07 — Valor por extenso determinístico (`AmountInWords`)
      Arquivos: `app/services/scan_solo/quote/amount_in_words.rb` (novo), `spec/services/scan_solo/quote/amount_in_words_spec.rb` (novo)
      Mudança: função pura pt-BR (reais/centavos, até 999.999.999,99, `ArgumentError` para ≤ 0), com palavras de `scan_solo.amount_in_words.*`.
      Cobre: RF-47, CT-05
      Acceptance criteria: `12500.00` → "doze mil e quinhentos reais"; `1.00` → "um real"; `1000.00` → "mil reais"; `1234567.89` → "um milhão, duzentos e trinta e quatro mil, quinhentos e sessenta e sete reais e oitenta e nove centavos"; `0.50` → "cinquenta centavos"; `0` → `ArgumentError`.
      Testes: `spec/services/scan_solo/quote/amount_in_words_spec.rb` — tabela acima.
- [ ] T08 — Origem do lead: classificador, bootstrap e backfill
      Arquivos: `app/services/scan_solo/pipeline/lead_source_classifier.rb` (novo), `app/services/scan_solo/pipeline/opportunity_bootstrap_service.rb`, `lib/tasks/scansolo.rake`, `spec/services/scan_solo/pipeline/lead_source_classifier_spec.rb` (novo), `spec/services/scan_solo/pipeline/opportunity_bootstrap_service_spec.rb`, `spec/lib/tasks/scansolo_rake_spec.rb`
      Mudança:
        • O classificador pega a 1ª mensagem não privada `incoming`/`outgoing` por `created_at`: `incoming` → `website`; `outgoing` de `User` → `manual`; senão nil.
        • O bootstrap grava `lead_source` no bloco do `create_or_find_by!` e no payload da auditoria.
        • Rake `scansolo:backfill_lead_source` com `update_columns` só quando o resultado não é nulo.
      Cobre: RF-01, RF-02, RF-03
      Acceptance criteria: os 3 casos do RF-02 e os 4 do RF-03 corretos; nota privada/`activity` ignoradas; 2ª execução do backfill → 0 alterações; contagens de `PipelineStageEvent`/`CadenceEnrollment`/`LeadStateEvent` e `updated_at` inalterados; `website` × `manual` em `em_contato` → mesma `CadenceDefinition` e mesmos `scheduled_at` relativos.
      Testes: os 3 specs listados — classificação, bootstrap e backfill idempotente.
- [ ] T09 — `ManualLeadService` (cadastro "Novo lead")
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

- [ ] T10 — Template inicial do lead manual e falha visível (RF-07, RF-08)
      Arquivos: `app/services/scan_solo/pipeline/manual_lead_outreach.rb` (novo), `app/services/scan_solo/pipeline/manual_lead_service.rb`, `app/services/scan_solo/conversation_listener.rb`, `app/services/scan_solo/messaging/delivery_reconciler.rb`, `spec/services/scan_solo/pipeline/manual_lead_outreach_spec.rb` (novo), `spec/services/scan_solo/messaging/delivery_reconciler_spec.rb`
      Mudança:
        • `ManualLeadOutreach`: resolve o slot `lead_manual_inicial` + guard; bloqueado → auditoria `pipeline.manual_lead_template_blocked`; senão `NativeTemplateSender` com origem `manual_lead`.
        • `ManualLeadService` chama o outreach via `after_all_transactions_commit`.
        • `TEMPLATE_ORIGINS` += `manual_lead`.
        • O reconciliador audita `pipeline.manual_lead_template_failed` com `external_error`, 1 vez por mensagem.
      Cobre: RF-07, RF-08, RNF-01
      Acceptance criteria: 1 `Message` de template com `scansolo_origin: 'manual_lead'` e o nome mapeado; 0 HTTP direto; `ai_control_state` `ai_active`; guard bloqueado → 0 mensagens + 1 auditoria com `reason`; mensagem `failed` → 1 auditoria com `external_error`, sem duplicar em novo update; `transaction_open?` falso no envio.
      Testes: `manual_lead_outreach_spec.rb`, `delivery_reconciler_spec.rb` — envio, bloqueio, falha e RNF-01.
- [ ] T11 — Leitura CT-02 (index/show/proposals) com queries constantes
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

- [ ] T12 — Endpoint `POST /pipeline_opportunities` (CT-01)
      Arquivos: `config/routes.rb`, `app/controllers/api/v1/accounts/scan_solo/pipeline_opportunities_controller.rb`, `app/policies/scan_solo/pipeline_opportunity_policy.rb`, `app/views/api/v1/accounts/scan_solo/pipeline_opportunities/create.json.jbuilder` (novo), `spec/requests/api/v1/accounts/scan_solo/pipeline_opportunities_create_spec.rb` (novo)
      Mudança:
        • Rota `create`; `create?` = `account_user.present?`.
        • Borda 422: `missing_name`, `invalid_phone` (regex E.164 do `Contact`), `invalid_email`, `invalid_owner`, `invalid_inbox` (WhatsApp na allowlist publicada; omitido só com exatamente 1).
        • `ManualLeadRejected` → 422 com código e `opportunity_id`.
        • 201 com show + `contact_created`.
      Cobre: CT-01, RF-05, RF-09, UI-01
      Acceptance criteria: as 7 condições do RF-05 → 422 com o código e contagens de `Contact`/`Conversation`/`PipelineOpportunity`/`Message` inalteradas; `opportunity_exists` → 422 com `opportunity_id`; 201 com `lead_source: manual`, `stage: novo_lead`, `contact_created` e `lead_state`; 404 com o flag desligado; regra do inbox único/múltiplo.
      Testes: `pipeline_opportunities_create_spec.rb` — 422s, 201 e 404.
- [ ] T13 — Interrupção da tentativa pendente a cada resposta (RF-43)
      Arquivos: `app/services/scan_solo/cadence/reply_interruption_service.rb` (novo), `app/services/scan_solo/conversation_listener.rb`, `app/services/scan_solo/cadence/reply_completeness_detector.rb`, `app/services/scan_solo/ai_turn/turn_orchestrator.rb` (só comentário), `spec/services/scan_solo/cadence/reply_interruption_service_spec.rb` (novo), `spec/services/scan_solo/cadence/reply_completeness_detector_spec.rb`, `spec/services/scan_solo/conversation_listener_spec.rb`
      Mudança:
        • Serviço com `enrollment.with_lock`: ciclo = última `outgoing` não privada antes da mensagem.
        • Já houve auditoria `cadence.attempt_interrupted_by_reply` depois disso → nada; senão cancela a próxima `scheduled` via `AttemptEvidenceRecorder` + 1 auditoria `{enrollment_id, attempt_id, message_id}`.
        • Chamado no listener (ramo não-criado, depois da regra de entrada).
        • O detector perde o ramo parcial (só "completa → cancela tudo").
      Cobre: RF-43, RF-44
      Acceptance criteria: parcial → próxima `cancelled` + 1 auditoria mesmo com turno `superseded`/`failed`; rajada de 3 sem saída → 1 cancelamento, demais `scheduled_at` intactos, `sent` intactas; cliente → saída → cliente → 2; matrícula posterior à mensagem → 0; detector parcial → 0 cancelamentos (expectativa alterada pelo RF-43, citada conforme RNF-11); `git diff main -- db/seeds/scansolo_cadence_definitions.rb` vazio.
      Testes: `reply_interruption_service_spec.rb`, `reply_completeness_detector_spec.rb`, `conversation_listener_spec.rb` — ciclos e independência do turno.

## Phase 6: E-mail nativo — composição, caixa de orçamento e leitura do bloco

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-operacao-centralizada/asyncapi.yaml` — `quoteRequestEmail` (CT-03), `quoteReplyEmail` (CT-04), `ParsedQuoteBlock`

- [ ] T14 — Composição dos e-mails (CT-03): solicitação, correção e negociação
      Arquivos: `app/services/scan_solo/quote/email_composer.rb` (novo), `spec/services/scan_solo/quote/email_composer_spec.rb` (novo)
      Mudança:
        • Puro; devolve `Email(subject, text, html)`, com HTML em `<br>` e valores escapados.
        • `.request(opportunity:, projection:)`: identificação (inclui o link `/app/accounts/<id>/conversations/<display_id>`), campos ≠ faltante com "(a confirmar)" nos inferidos e bloco vazio CT-04.
        • `.correction(problems:)` e `.negotiation(payload:)` (9 itens).
        • Textos do `en.yml`.
      Cobre: CT-03, RF-13, RF-18, RF-37, RNF-07, RNF-08
      Acceptance criteria: `request` contém id, rótulos e valores `confirmado`/`inferido`, "(a confirmar)" só nos inferidos e as 5 linhas de rótulo entre delimitadores; sem valor `faltante` nem `api_access_token`; `<br>` entre campos; `correction([:payment_terms])` contém "Condições de pagamento" e o bloco; `negotiation` contém os 9 itens e o link.
      Testes: `spec/services/scan_solo/quote/email_composer_spec.rb` — 3 composições.
- [ ] T15 — Caixa de orçamento e thread de e-mail nativa
      Arquivos: `app/services/scan_solo/quote/mailbox.rb` (novo), `app/services/scan_solo/quote/email_thread.rb` (novo), `lib/custom_exceptions/scan_solo.rb`, `spec/services/scan_solo/quote/mailbox_spec.rb` (novo), `spec/services/scan_solo/quote/email_thread_spec.rb` (novo)
      Mudança:
        • sem destinatário fixo no código; `.resolve!(account)` devolve `Settings(inbox, recipient)` da config publicada (`quote_inbox_id`, `quote_recipient_email`) ou levanta `QuoteInboxMisconfigured` (`quote_inbox_missing|quote_inbox_not_email|quote_inbox_allowlisted`).
        • `EmailThread.open!(inbox:, recipient:, subject:, marker:)`: `ContactInboxWithContactBuilder` + `ConversationBuilder` com `mail_subject` e `scansolo_thread`.
        • `EmailThread.post!(conversation:, recipient:, email:)`: só fora de transação; `messages.create!` outgoing com `to_emails` e `email.html_content.reply`.
      Cobre: CT-03, RF-12, RF-14, RF-16, RF-37, RF-42, RNF-01, RNF-04
      Acceptance criteria: as 3 condições → exceção com o `reason`; destinatário alterado só no rascunho → `Settings` usa o publicado; `post!` → 1 e-mail (ActionMailer `:test`) com From = e-mail do canal, To = `[destinatário publicado]`, Subject = `mail_subject` e HTML com `<br>`; 2º `open!` reusa o contato; `post!` com `transaction_open?` falso.
      Testes: `mailbox_spec.rb`, `email_thread_spec.rb` — configuração e envio nativo.
- [ ] T16 — Leitura determinística do bloco (CT-04)
      Arquivos: `app/services/scan_solo/quote/response_block_parser.rb` (novo), `spec/services/scan_solo/quote/response_block_parser_spec.rb` (novo)
      Mudança:
        • Puro, sem LLM.
        • Pré-processamento: ignora linhas `>`, normaliza caixa/acentos/espaços/marcadores; rótulos do `en.yml`; delimitadores opcionais; HTML convertido quando o texto é vazio.
        • Bloco: o 1º com ≥ 1 rótulo preenchido; cada valor até o próximo rótulo, o FIM ou a citação.
        • Valor pela gramática CT-04 (> 0); `problems` para obrigatórios vazios ou ilegíveis.
      Cobre: CT-04, RF-17, RF-18, RF-21
      Acceptance criteria: resposta no topo + citação vazia → 4 campos aparados e `R$ 12.500,00` → `12500.00`; variações toleradas dão os mesmos valores; escopo multilinha preservado; `12500.00` e `0,00` → `[:total_value]`; sem "Condições de pagamento" → `[:payment_terms]`; só citação → 4 problemas; só HTML → mesmos valores; 0 chamadas a `ModelInvoker`/`RubyLLM`.
      Testes: `spec/services/scan_solo/quote/response_block_parser_spec.rb` — tabela de variações.

