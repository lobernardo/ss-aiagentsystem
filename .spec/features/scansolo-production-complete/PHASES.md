# Phases: scansolo-production-complete

Gerado por /plan a partir de PLAN.md — view executável para `./ralph.sh .spec/features/scansolo-production-complete/PHASES.md`.

Regras transversais (de `AGENTS.md`/`CLAUDE.md`, `docs/agents/architecture.md`, `docs/agents/domain_rules.md`): controllers só fazem gate 404, escopo `Current.account`, `authorize`, strong params e validação 422, delegando toda escrita a services; jobs não possuem lógica de elegibilidade; o listener não possui lógica de IA; writers únicos preservados (`StageTransitionService`, `EnrollmentService`, `TakeoverService`/`ReturnToAiService`, `CallbackHandler`, `Actions::Registry`); nenhuma dependência de `enterprise/` em `app/**/scan_solo/**`; copy só em `en/scansolo.json`/`en.yml`; Vue `<script setup>` + Tailwind; nunca tocar Nginx/TLS/domínio; nunca executar deploy/ativação de provider.

## Phase 1: Fundação P0 — esquema, elegibilidade, configuração, políticas

Antes de implementar, leia:
1. `.spec/features/scansolo-production-complete/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-production-complete/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-production-complete/openapi.yaml` — contrato CT-01 e CT-04 (T04, T06)

- [ ] T01 — Migrations aditivas e as duas substituições de índice (RNF-05)
      Arquivos: `db/migrate/20260923000001_add_production_fields_to_scan_solo_ai_agent_configs.rb`, `db/migrate/20260923000002_create_scan_solo_contact_extensions.rb`, `db/migrate/20260923000003_add_delivery_fields_to_scan_solo_cadence_attempts.rb`, `db/migrate/20260923000004_create_scan_solo_template_mappings.rb`, `db/migrate/20260923000005_add_index_state_to_scan_solo_knowledge_sources.rb`, `db/migrate/20260923000006_replace_scan_solo_cadence_enrollment_unique_index.rb`, `db/migrate/20260923000007_replace_scan_solo_make_callbacks_correlation_index.rb`, `db/schema.rb`
      Mudança: `allowed_inbox_ids jsonb []` e `opt_out_keywords jsonb ["PARAR","SAIR","STOP"]` em configs; tabela `scan_solo_contact_extensions` (contact_id único, opted_out, opted_out_at, opted_out_source); attempts ganham `message_id`, `last_block_reason`, `last_checked_at`, `external_error`; tabela `scan_solo_template_mappings` (account_id, stage, step null, template_name, language, params) único `(account_id, stage, step)` NULLS NOT DISTINCT; knowledge sources ganham `index_status`, `index_error`, `indexed_at`, `chunk_count`; índice único de enrollments vira parcial `status IN (0,1)`; índice único de `make_callbacks.correlation_id` vira parcial `applied = true`. Migrations 6 e 7 reversíveis, sem apagar linhas.
      Cobre: RNF-05, RF-03, RF-16, RF-27, RF-30, RF-32, RF-39, RF-44
      Depende de: nenhuma
      Acceptance criteria: migrate → rollback STEP=7 → migrate funcionam; só as migrations 6 e 7 removem índice e o recriam parcial; nenhum `remove_column`, `change_column` ou DELETE.
      Testes: `spec/db/scansolo_migrations_spec.rb` — DDL aditivo + predicados parciais asserted via `db/schema.rb`.
- [ ] T02 — Models: ContactExtension, TemplateMapping, novos enums e campos
      Arquivos: `app/models/scan_solo/contact_extension.rb`, `app/models/scan_solo/template_mapping.rb`, `app/models/scan_solo/cadence_attempt.rb`, `app/models/scan_solo/knowledge_source.rb`, `app/models/scan_solo/ai_agent_config.rb`, `app/models/scan_solo/cadence_enrollment.rb`, `app/models/scan_solo/make_callback.rb`
      Mudança: `ContactExtension.resolve_for` + `opted_out?`; `TemplateMapping` com `PARAM_SOURCES` (contact_name, contact_first_name, agent_name, stage_label, static) e validações; `CadenceAttempt` enum `dispatched: 5` + `belongs_to :message`; `KnowledgeSource` enum `index_status`; `AiAgentConfig::FIELDS` inclui `allowed_inbox_ids` e `opt_out_keywords`; scope `CadenceEnrollment.open_for`; scope `MakeCallback.applied`.
      Cobre: RF-03, RF-16, RF-27, RF-30, RF-32, RF-44, RF-63
      Depende de: T01
      Acceptance criteria: publicar copia `allowed_inbox_ids`/`opt_out_keywords`; mapping com source `phone_number` inválido; `CadenceAttempt.results` inclui `dispatched`; 4 valores de `index_status`.
      Testes: `spec/models/scan_solo/contact_extension_spec.rb`, `spec/models/scan_solo/template_mapping_spec.rb`, `spec/models/scan_solo/cadence_attempt_spec.rb`, `spec/services/scan_solo/ai_agent/publish_service_spec.rb`
- [ ] T03 — `ScanSolo::Eligibility`: gate único (flag + allowlist + sem bot ativo)
      Arquivos: `app/services/scan_solo/eligibility.rb`, `spec/services/scan_solo/eligibility_spec.rb`, `spec/enterprise/services/scan_solo/captain_exclusivity_spec.rb`
      Mudança: `Eligibility.for_inbox(account:, inbox:)` / `.for_message(message)` → `Result(eligible?, reason)` com `scansolo_disabled`, `inbox_not_allowlisted`, `inbox_has_active_bot`, `config_unavailable`; usa config publicada (allowlist vazia = fail closed) e `inbox.active_bot?`; sem referência a `Captain::`. Definição única reutilizada por listener, recheck pré-envio e precheck de cadência.
      Cobre: RF-01, RF-02, RF-03, RNF-09
      Depende de: T02
      Acceptance criteria: cada condição falha com sua razão; todas satisfeitas → elegível; `grep -rn "Captain" app/services/scan_solo` vazio; `spec/lib/scansolo_no_enterprise_dependency_spec.rb` verde.
      Testes: `spec/services/scan_solo/eligibility_spec.rb` — 4 razões + caminho elegível; `spec/enterprise/services/scan_solo/captain_exclusivity_spec.rb` — Captain ativo → `inbox_has_active_bot`.
- [ ] T04 — API do Agent Config: allowlist, opt-out keywords, modelos disponíveis (CT-01 P0)
      Arquivos: `app/controllers/api/v1/accounts/scan_solo/ai_agent_configs_controller.rb`, `app/views/api/v1/accounts/scan_solo/ai_agent_configs/_ai_agent_config.json.jbuilder`, `app/views/api/v1/accounts/scan_solo/ai_agent_configs/show.json.jbuilder`, `app/services/scan_solo/ai_agent/model_resolver.rb`
      Mudança: strong params `allowed_inbox_ids: []`, `opt_out_keywords: []`; 422 na borda para inbox de outra conta ou `model_selection` fora de `scansolo_agent_response` (`config/llm.yml`); GET expõe `available_models`; `ModelResolver` expõe a lista e deixa de fazer fallback silencioso.
      Cobre: RF-03, RF-16, UI-08, CT-01
      Depende de: T02
      Acceptance criteria: inbox de outra conta → 422; `model_selection: "foo"` → 422; GET retorna `available_models` com os 4 modelos, `allowed_inbox_ids` e `opt_out_keywords` default.
      Testes: `spec/requests/api/v1/accounts/scan_solo/ai_agent_configs_spec.rb`
- [ ] T05 — Policies admin-only e regras de proposta (RF-48)
      Arquivos: `app/policies/scan_solo/ai_agent_config_policy.rb`, `app/policies/scan_solo/knowledge_source_policy.rb`, `app/policies/scan_solo/proposal_policy.rb`, `app/policies/scan_solo/template_mapping_policy.rb`, `app/policies/scan_solo/contact_opt_out_policy.rb`, `app/policies/scan_solo/status_policy.rb`, `app/policies/scan_solo/application_policy.rb`
      Mudança: helper `administrator?`; config draft/publish admin; knowledge create/update/destroy/reindex/retrieval_tests admin; proposal generate qualquer, approve admin, send admin ou `opportunity.owner_id == user.id`, retry admin; novas policies template mapping (update admin), contact opt-out (destroy admin), status (show admin). Leituras continuam para qualquer usuário da conta.
      Cobre: RF-48, RF-60, RF-63, UI-13
      Depende de: T02
      Acceptance criteria: agente recebe 403 em draft/publish/escritas de knowledge/reindex/retrieval/approve/retry; owner agente 2xx em send, não-owner 403; admin 2xx; nenhuma policy de escrita retorna `true` incondicional.
      Testes: `spec/policies/scan_solo/*_policy_spec.rb` (6 arquivos); request specs `ai_agent_configs_spec.rb`, `knowledge/sources_spec.rb`, `proposals_spec.rb` — matriz 403/2xx.
- [ ] T06 — Resolver de integração de proposta e bloqueio do mock (RF-35, RF-36)
      Arquivos: `app/services/scan_solo/proposal/integration.rb`, `app/services/scan_solo/proposal/make_provider.rb`, `lib/custom_exceptions/scan_solo.rb`, `app/controllers/api/v1/accounts/scan_solo/base_controller.rb`, `app/services/scan_solo/proposal/generate_service.rb`, `app/services/scan_solo/proposal/send_service.rb`, `app/services/scan_solo/proposal/retry_policy.rb`, `app/services/scan_solo/actions/proposal_actions.rb`
      Mudança: `Integration.configured?` (3 credenciais `scan_solo.make.*`), `.state`, `.provider!` (Mock só em test/dev; MakeProvider quando configurado; senão `CustomExceptions::ScanSolo::ProposalIntegrationNotConfigured`); remover defaults `MockProvider`; `MakeProvider` delega ao `OutboundRequestService`; `BaseController` converte a exceção em 422 `{error: "proposal_integration_not_configured"}` antes de criar linhas.
      Cobre: RF-35, RF-36, CT-04
      Depende de: T02
      Acceptance criteria: em env production sem credenciais, generate/send/retry → 422 com o código, 0 `ProposalVersion`, 0 `MakeRequest`; `MockProvider` nunca chamado; `1500.0`/`mock-proposals.scansolo.test` nunca persistidos.
      Testes: `spec/services/scan_solo/proposal/integration_spec.rb`, `spec/requests/api/v1/accounts/scan_solo/proposals_spec.rb`
- [ ] T07 — Redação de log preservando UUID/correlation id (RNF-03)
      Arquivos: `app/services/scan_solo/ai_turn/prompt_redactor.rb`
      Mudança: excluir valores no formato UUID da regra de token longo; manter `sk-`, Bearer e tokens opacos ≥ 32 não-UUID redigidos.
      Cobre: RNF-03, RNF-04
      Depende de: nenhuma
      Acceptance criteria: linha com UUID e chave `sk-...` mantém o UUID e mostra `[REDACTED]` para a chave.
      Testes: `spec/services/scan_solo/ai_turn/prompt_redactor_spec.rb`

## Phase 2: Runtime P0 — pipeline, opt-out, handoff, listener, turno de IA, ações

Antes de implementar, leia:
1. `.spec/features/scansolo-production-complete/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-production-complete/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-production-complete/asyncapi.yaml` — CT-09 (eventos nativos consumidos pelo listener, T11)

- [ ] T08 — Bootstrap da oportunidade, enroll por estágio e re-enroll (RF-22, RF-23, RF-24, RF-30)
      Arquivos: `app/services/scan_solo/pipeline/opportunity_bootstrap_service.rb`, `app/services/scan_solo/cadence/stage_entry_enroller.rb`, `app/services/scan_solo/pipeline/stage_transition_service.rb`, `app/services/scan_solo/proposal/success_handler.rb`, `app/services/scan_solo/cadence/enrollment_service.rb`
      Mudança: bootstrap `create_or_find_by!(conversation_id:)` em `novo_lead` (owner = assignee) + `AuditEvent pipeline.opportunity_created` + enroll; `StageEntryEnroller` para novo_lead/em_contato/em_qualificacao/proposta_enviada (pula opted-out; definição ausente → `ChatwootExceptionTracker` + `AuditEvent cadence.definition_missing`); `StageTransitionService` chama o enroller após commit; `SuccessHandler` perde o enroll silencioso; `EnrollmentService` retorna o enrollment aberto do par ou cria novo.
      Cobre: RF-22, RF-23, RF-24, RF-30
      Depende de: T01, T02
      Acceptance criteria: 1º bootstrap → 1 oportunidade `novo_lead` + enrollment Novo Lead + 1 audit; 2 chamadas concorrentes → 1 linha; cada uma das 4 entradas de estágio → 1 enrollment ativo; sem definições → tracker + 1 audit; cancel + enroll → 2 linhas; enroll duplo ativo → 1 linha.
      Testes: `spec/services/scan_solo/pipeline/opportunity_bootstrap_service_spec.rb`, `spec/services/scan_solo/cadence/stage_entry_enroller_spec.rb`, `spec/services/scan_solo/cadence/enrollment_service_spec.rb`, `spec/services/scan_solo/proposal/success_handler_spec.rb`
- [ ] T09 — Opt-out: palavra-chave determinística, marcação e limpeza (RF-16, RF-31, RF-63)
      Arquivos: `app/services/scan_solo/opt_out/keyword_matcher.rb`, `app/services/scan_solo/opt_out/mark_service.rb`, `app/services/scan_solo/opt_out/clear_service.rb`, `app/services/scan_solo/actions/cadence_signal_action.rb`
      Mudança: `KeywordMatcher` normaliza os dois lados (trim, case-insensitive, sem acento via `I18n.transliterate`, sem pontuação) e compara a mensagem inteira, sem chamar modelo; `MarkService` marca `ContactExtension` e cancela enrollments ativos/pausados via `StopRecalculatePolicy` `opt_out`; `ClearService` desmarca + `AuditEvent contact.opt_out_cleared`; `CadenceSignalAction` `opt_out` usa `MarkService`.
      Cobre: RF-16, RF-31, RF-63
      Depende de: T02
      Acceptance criteria: `Parar!`, `  sair `, `stop.`, `PÁRAR` casam; `não vou parar agora`, `parar de receber?` não; marcação deixa 0 enrollments ativos/pausados; clear → false + 1 audit.
      Testes: `spec/services/scan_solo/opt_out/keyword_matcher_spec.rb`, `mark_service_spec.rb`, `clear_service_spec.rb`, `spec/services/scan_solo/actions/cadence_signal_action_spec.rb`
- [ ] T10 — Handoff: pausa no takeover, recálculo no retorno, status da proposta na nota (RF-19, RF-20, RF-21, RF-29)
      Arquivos: `app/services/scan_solo/cadence/stop_recalculate_policy.rb`, `app/services/scan_solo/cadence/resume_on_return_service.rb`, `app/services/scan_solo/handoff/return_to_ai_service.rb`, `app/services/scan_solo/handoff/handoff_service.rb`
      Mudança: `handle_takeover` pausa (não cancela); trigger `handoff` em `TRIGGERS` e `PAUSING_TRIGGERS`; `ResumeOnReturnService` retoma o enrollment pausado do estágio atual via `LifecycleService.resume!` ou cria via `StageEntryEnroller` (salvo opt-out); `ReturnToAiService` (único caminho para `ai_active`) o chama; nota de handoff mostra o status pt-BR da versão atual da proposta.
      Cobre: RF-19, RF-20, RF-21, RF-29
      Depende de: T08
      Acceptance criteria: takeover → enrollments `paused`, attempts `scheduled`; takeover 30 h + retorno → próximo `scheduled_at` = original + 30 h; retorno sem enrollment aberto → novo enrollment (exceto opt-out); nota com versão `generated` mostra o rótulo pt-BR.
      Testes: `spec/services/scan_solo/cadence/stop_recalculate_policy_spec.rb`, `spec/services/scan_solo/cadence/resume_on_return_service_spec.rb`, `spec/services/scan_solo/handoff/return_to_ai_service_spec.rb`, `spec/services/scan_solo/handoff/handoff_service_spec.rb`
- [ ] T11 — Listener: gate único, bootstrap, opt-out por palavra-chave, takeover implícito, marcação de origem (RF-01, RF-02, RF-16, RF-18, RF-22, RF-23)
      Arquivos: `app/services/scan_solo/conversation_listener.rb`, `app/services/scan_solo/handoff/takeover_service.rb`, `app/services/scan_solo/ai_turn/response_sender.rb`, `app/services/scan_solo/messaging/native_template_sender.rb`
      Mudança: incoming → `Eligibility.for_message` antes de qualquer escrita; bootstrap (mensagem criadora não aplica `InboundMessageTransitionRule`; demais registram interação + regra); `KeywordMatcher` + `MarkService` independente do turno; enqueue `AiTurnJob`. Outgoing não-privada com sender `User`, sem `scansolo_origin`, estado ≠ `human_active` → `TakeoverService(trigger: 'human_reply')`. `ResponseSender` marca `scansolo_origin: 'ai'`; `NativeTemplateSender` aceita `origin:` (`cadence`/`proposal`). Listener sem lógica de IA.
      Cobre: RF-01, RF-02, RF-16, RF-18, RF-22, RF-23, CT-09
      Depende de: T03, T08, T09, T10
      Acceptance criteria: cada condição de elegibilidade falha → 0 oportunidades, 0 turnos, 0 enqueues; todas ok → 1 enqueue; mensagem criadora → `novo_lead`, segunda → `em_contato` + Novo Lead cancelado + Em Contato ativo; `PARAR` → marcador true; resposta de agente → `human_active` + 1 `handoff.takeover` com `trigger: human_reply`; nota privada, atribuição manual, auto-atribuição, mensagem de cadência e de proposta → estado inalterado e 0 eventos.
      Testes: `spec/services/scan_solo/conversation_listener_spec.rb`, `spec/services/scan_solo/handoff/takeover_service_spec.rb`, `spec/integration/scan_solo/implicit_takeover_spec.rb`
- [ ] T12 — Prompt completo, saída estruturada, restricted_information, evidência RAG, latência (RF-05, RF-06, RF-46, RF-59)
      Arquivos: `app/services/scan_solo/ai_turn/prompt_builder.rb`, `app/services/scan_solo/ai_turn/model_invoker.rb`, `app/services/scan_solo/ai_turn/output_validator.rb`, `app/services/scan_solo/ai_turn/context_assembler.rb`, `app/services/scan_solo/test_mode/mock_llm_provider.rb`
      Mudança: `PromptBuilder` monta system message pt-BR com as 12 regras (horário/limites como instrução, D-22) e os 5 blocos de contexto (histórico como chat, chunks com títulos, contato, oportunidade com campos coletados/faltantes, memória), payload inteiro via `PromptRedactor`; `ModelInvoker` usa saída estruturada `{reply, actions[]}`, mede `latency_ms`, não engole exceções não-provider; `OutputValidator` bloqueia `restricted_information`; `ContextAssembler` devolve chunks `{source_id, source_title, chunk_id, similarity_score}` (queda → `[]` + razão); `MockLlmProvider` no mesmo formato e captura o payload.
      Cobre: RF-05, RF-06, RF-46, RF-59
      Depende de: T02
      Acceptance criteria: payload capturado contém os 12 campos e os 5 blocos com redação aplicada; saída com entrada restrita → bloqueio `restricted_information`; evidência = chunks do prompt; queda → `[]` + razão.
      Testes: `spec/services/scan_solo/ai_turn/prompt_builder_spec.rb`, `model_invoker_spec.rb`, `output_validator_spec.rb`, `context_assembler_spec.rb`
- [ ] T13 — Orquestrador: estados terminais, retry idempotente, lock por conversa, recheck pré-envio (RF-02, RF-04, RF-07, RF-08, RF-09, RF-10, RF-11, RF-28, RNF-01)
      Arquivos: `app/services/scan_solo/ai_turn/turn_orchestrator.rb`, `app/jobs/scan_solo/ai_turn_job.rb`, `app/services/scan_solo/ai_turn/response_sender.rb`, `app/services/scan_solo/ai_turn/eligibility_guard.rb`
      Mudança: turno existente terminal → no-op; `pending` sem resposta → retoma mesma linha/correlation; `rescue StandardError` → `failed` com classe + mensagem redigida + `ChatwootExceptionTracker` com correlation id; mutex Redis por conversa (`Redis::LockManager`, TTL > timeout do modelo) em invocação+envio, job re-enfileira na contenção (`retry: 3`); antes de invocar, gatilho não-mais-recente → `suppressed/superseded`; transação de envio com `ConversationExtension#with_lock` + recheck (`not_eligible`/`inbox_has_active_bot`, `human_controlled`, `config_unavailable`, `human_replied`, `superseded`, turno ainda `pending`) → falha = `suppressed` + rollback; depois ações (T14) e `ResponseSender`; ao final `ReplyCompletenessDetector`.
      Cobre: RF-02, RF-04, RF-07, RF-08, RF-09, RF-10, RF-11, RF-19, RF-28, RNF-01
      Depende de: T03, T11, T12
      Acceptance criteria: `StandardError` em cada um dos 7 estágios → `failed` + tracker 1x; job 2x após crash simulado → 1 turno, 1 correlation, ≤ 1 mensagem; 5 checks invertidos → 0 mensagens com as 5 razões; modelo lento + 3 incoming em 2 s → 1 resposta, 2 `superseded`, payload sobrevivente com os 3 textos; flag off no meio → suppressed; resposta completa → 0 attempts `scheduled`; parcial → só o próximo cancelado.
      Testes: `spec/services/scan_solo/ai_turn/turn_orchestrator_spec.rb`, `spec/jobs/scan_solo/ai_turn_job_spec.rb`, `spec/integration/scan_solo/burst_single_reply_spec.rb`, `spec/integration/scan_solo/presend_recheck_spec.rb`
- [ ] T14 — Ações da IA exclusivamente via Registry (RF-12, RF-13, RF-14, RF-15, RF-16a, RF-17)
      Arquivos: `app/services/scan_solo/ai_turn/turn_orchestrator.rb`, `app/services/scan_solo/ai_turn/input_guardrail.rb`, `app/services/scan_solo/actions/stage_transition_action.rb`, `app/services/scan_solo/actions/handoff_action.rb`, `app/services/scan_solo/actions/registry.rb`
      Mudança: remover `SUPPORTED_ACTIONS`, `actions:` e `execute_stage_transition`; após o recheck, `Actions::Registry.call` por ação com correlation do turno e chave `"#{correlation_id}:#{index}:#{action_id}"`; ids oferecidos: qualification_field, stage_transition, private_note, cadence_signal, human_handoff + proposal_generate só se `Proposal::Integration.configured?`; erro do executor → turno `failed`, 0 mensagens; `StageTransitionAction` só avança para em_qualificacao/qualificado (rejeição em `action_evidence`); `HandoffAction` → `HandoffService` (`awaiting_human` + nota) + pausa `handoff`, resposta do próprio turno enviada; chamada HTTP Make do `proposal_generate` só após commit.
      Cobre: RF-12, RF-13, RF-14, RF-15, RF-16, RF-17
      Depende de: T06, T10, T13
      Acceptance criteria: uma ação de cada id → 1 `AgentActionExecution` cada com a correlation do turno; re-run → 0 novas; `grep -n execute_stage_transition app/services/scan_solo` vazio; id não registrado → `failed`, 0 mensagens, 0 efeitos; 5 alvos proibidos inalterados + evidência; `em_contato → em_qualificacao` com `PipelineStageEvent`; handoff → 1 nota, `awaiting_human`, enrollments `paused`, próximo incoming → 0 respostas; último campo via ação → attempts restantes cancelados.
      Testes: `spec/services/scan_solo/ai_turn/turn_orchestrator_actions_spec.rb`, `spec/services/scan_solo/actions/stage_transition_action_spec.rb`, `spec/services/scan_solo/actions/handoff_action_spec.rb`
- [ ] T15 — Sweeper de turnos pending (RF-08, RNF-02)
      Arquivos: `app/jobs/scan_solo/stale_turn_sweeper_job.rb`, `config/schedule.yml`, `config/initializers/scansolo_constants.rb`
      Mudança: `ScanSolo::AI_TURN_STALE_THRESHOLD = 10.minutes`; job marca `pending` mais antigos `failed/stale_pending` (com lock); cron `scan_solo_stale_turn_sweeper_job` `*/5 * * * *` na fila `scheduled_jobs`.
      Cobre: RF-08, RNF-02
      Depende de: T13
      Acceptance criteria: turno criado há 11 min → `failed/stale_pending` após a execução; job posterior da mensagem envia 0; entrada no schedule presente.
      Testes: `spec/jobs/scan_solo/stale_turn_sweeper_job_spec.rb`

## Phase 3: Cadências, templates, conhecimento, APIs e status P0

Antes de implementar, leia:
1. `.spec/features/scansolo-production-complete/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-production-complete/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-production-complete/openapi.yaml` — CT-02, CT-03, CT-07, CT-08, CT-11 (T17, T21, T22, T23, T24)
4. `.spec/features/scansolo-production-complete/asyncapi.yaml` — CT-09 `message.updated` (T19)

- [ ] T16 — Resolver de template e guard de disponibilidade nativo (RF-32, RF-33, RF-34)
      Arquivos: `app/services/scan_solo/messaging/template_resolver.rb`, `app/services/scan_solo/cadence/template_availability_guard.rb`, `app/services/scan_solo/messaging/native_template_sender.rb`, `spec/lib/scansolo_native_whatsapp_only_spec.rb`
      Mudança: `TemplateResolver` usa `TemplateMapping` ou a convenção `scansolo_cadence_<stage>_v<version>_step<n>` + `pt_BR` sem params; params só das 5 fontes permitidas em `processed_params`; guard (cadência e envio de proposta) compara nome+idioma+status e contagem `{{n}}` do BODY → `template_missing`, `template_rejected`, `template_paused`, `template_pending`, `template_disabled`, `language_unavailable`, `params_mismatch` + `message_templates_last_updated`; inbox não-WhatsApp segue disponível; envio só via `conversation.messages.create!` nativo.
      Cobre: RF-32, RF-33, RF-34
      Depende de: T02, T11
      Acceptance criteria: passo mapeado → `template_params` com nome, idioma e params resolvidos; não mapeado → convenção + `pt_BR`; 7 fixtures → 0 mensagens + razão + último sync; grep `graph.facebook.com|evolution` em `app/**/scan_solo` → 0.
      Testes: `spec/services/scan_solo/messaging/template_resolver_spec.rb`, `spec/services/scan_solo/cadence/template_availability_guard_spec.rb`, `spec/lib/scansolo_native_whatsapp_only_spec.rb`
- [ ] T17 — API de mapeamento de templates (CT-03)
      Arquivos: `app/controllers/api/v1/accounts/scan_solo/cadence_templates_controller.rb`, `app/views/api/v1/accounts/scan_solo/cadence_templates/index.json.jbuilder`, `app/views/api/v1/accounts/scan_solo/cadence_templates/_row.json.jbuilder`, `app/services/scan_solo/messaging/template_mapping_upsert_service.rb`, `app/services/scan_solo/messaging/template_availability_report.rb`, `config/routes.rb`
      Mudança: `GET/PUT /cadence_templates`; GET monta uma linha por (stage, step) das definições ativas + linha de envio de proposta (`step: null`) via `TemplateAvailabilityReport` (guard T16 sobre inboxes WhatsApp da allowlist); PUT valida fonte na borda (422), `TemplateMappingPolicy#update?`, delega ao upsert service.
      Cobre: RF-32, RF-33, UI-12, CT-03
      Depende de: T05, T16
      Acceptance criteria: GET com linhas por estágio/passo + linha de proposta com disponibilidade/razão/status Meta/último sync; PUT com `source: "phone_number"` → 422; agente → 403.
      Testes: `spec/requests/api/v1/accounts/scan_solo/cadence_templates_spec.rb`
- [ ] T18 — Job de cadência: pré-checagens, adiamento sem consumo, dispatched (RF-04, RF-26, RF-27, RF-29, RF-31, RNF-08)
      Arquivos: `app/services/scan_solo/cadence/attempt_precheck.rb`, `app/jobs/scan_solo/cadence_due_attempt_job.rb`, `app/services/scan_solo/cadence/attempt_evidence_recorder.rb`
      Mudança: `AttemptPrecheck` (job sem lógica de elegibilidade) em ordem sob o lock: opt-out → cancela `opt_out`; conversa `resolved` → cancela `conversation_resolved`; flag off/config ausente/`Eligibility.for_inbox` falso/estado ≠ `ai_active` → adia; guard T16 bloqueado → adia. Adiar mantém `scheduled`, grava `last_block_reason`/`last_checked_at`, não mexe em `current_step`. Envio `NativeTemplateSender(origin: 'cadence')` → `record_dispatched!` (nunca `sent`); envio atrasado desloca os attempts seguintes pelo atraso; no máximo 1 attempt por enrollment por execução.
      Cobre: RF-04, RF-26, RF-27, RF-29, RF-31, RNF-08
      Depende de: T03, T09, T16
      Acceptance criteria: um spec por pré-checagem com resultado/razão; (3)/(4) mantêm `scheduled`, `current_step` igual, 0 mensagens; flag off → 0 envios e 0 mudanças; WhatsApp → `dispatched` + message id; re-run nunca reenvia `dispatched`; step-1 adiado 26 h → step-2 desloca 26 h e não sai na mesma execução.
      Testes: `spec/jobs/scan_solo/cadence_due_attempt_job_spec.rb`, `spec/services/scan_solo/cadence/attempt_precheck_spec.rb`
- [ ] T19 — Reconciliador de entrega (RF-27, RF-41, CT-09)
      Arquivos: `app/services/scan_solo/messaging/delivery_reconciler.rb`, `app/services/scan_solo/conversation_listener.rb`, `app/services/scan_solo/proposal/callback_handler.rb`
      Mudança: listener `message_updated` → `DeliveryReconciler` para mensagens de `CadenceAttempt.message_id` ou `ProposalVersion.sent_message_id`: `source_id` + status ≠ failed → `sent` + `sent_at`; `failed` → grava `external_error`; não-WhatsApp persistida não-failed = aceita. `CallbackHandler.apply_send_result!` deixa de marcar `sent`/chamar `SuccessHandler`; o reconciliador marca a versão `sent` + `SuccessHandler` ou `failed` com o erro, sem mudar estágio. Idempotente.
      Cobre: RF-27, RF-41, CT-09
      Depende de: T11, T18
      Acceptance criteria: update nativo com `source_id` → attempt `sent` + `sent_at`; nativo `failed` → attempt `failed` + erro externo; proposta com falha nativa → versão `failed`, estágio inalterado; aceita → `sent` + `proposta_enviada`.
      Testes: `spec/services/scan_solo/messaging/delivery_reconciler_spec.rb`, `spec/services/scan_solo/proposal/callback_handler_spec.rb`
- [ ] T20 — Carga idempotente das definições de cadência (RF-25)
      Arquivos: `lib/tasks/scansolo.rake`, `db/seeds/scansolo_cadence_definitions.rb`
      Mudança: `bundle exec rails scansolo:load_cadence_definitions` carrega o seed idempotente (offsets exatos do RF-25) e imprime as 4 definições ativas.
      Cobre: RF-25
      Depende de: nenhuma
      Acceptance criteria: rodar 2x em banco vazio → exatamente 4 linhas ativas com `[2,24,48,96]`, `[24,48,72,96,120]`, `[24,48,72,96,120,144,168]`, `[24,72,168]`.
      Testes: `spec/lib/tasks/scansolo_rake_spec.rb`
- [ ] T21 — Conhecimento: ingestão assíncrona, estado de indexação, reindex por conteúdo (RF-43, RF-44, RF-45)
      Arquivos: `app/jobs/scan_solo/knowledge_ingestion_job.rb`, `app/services/scan_solo/knowledge/ingestion_service.rb`, `app/services/scan_solo/knowledge/reindex_service.rb`, `app/models/scan_solo/knowledge_source.rb`, `app/controllers/api/v1/accounts/scan_solo/knowledge/sources_controller.rb`, `app/views/api/v1/accounts/scan_solo/knowledge/sources/_source.json.jbuilder`, `app/javascript/dashboard/routes/dashboard/scansolo/knowledge/KnowledgeCenter.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/knowledge/specs/KnowledgeCenter.spec.js`
      Mudança: create/reindex/`saved_change_to_content?` enfileiram `KnowledgeIngestionJob` (fila `low`) com `pending`; job → `indexing`, embeda antes de substituir chunks (queda preserva os anteriores), `indexed` + `indexed_at` + `chunk_count` ou `failed` + `index_error` pt-BR; 0 chunks → `failed`; jbuilder expõe `index_status`, `index_error`, `indexed_at`, `chunk_count` (substitui `chunks_count`, atualizando o consumidor `KnowledgeCenter.vue:156` e o fixture).
      Cobre: RF-43, RF-44, RF-45, CT-02
      Depende de: T02, T05
      Acceptance criteria: PATCH `content` → chunks com o novo texto após o job; PATCH só `enabled` → 0 jobs; sucesso → `indexed`, `chunk_count > 0`; queda de embedding → `failed` + erro, chunks anteriores preservados; só anexo → `failed` + razão; nenhuma resposta `indexed` com 0 chunks.
      Testes: `spec/jobs/scan_solo/knowledge_ingestion_job_spec.rb`, `spec/services/scan_solo/knowledge/ingestion_service_spec.rb`, `spec/requests/api/v1/accounts/scan_solo/knowledge/sources_spec.rb`, `KnowledgeCenter.spec.js`
- [ ] T22 — API de turnos: evidência, latência, status de entrega (RF-59, CT-08)
      Arquivos: `app/views/api/v1/accounts/scan_solo/ai_turns/_ai_turn.json.jbuilder`, `app/controllers/api/v1/accounts/scan_solo/ai_turns_controller.rb`
      Mudança: `knowledge_evidence` da coluna; adicionar `response_delivery_status` (`response_message&.status`); manter `latency_ms`, `failure_reason`, `action_evidence`; `includes(:response_message)`.
      Cobre: RF-46, RF-59, CT-08
      Depende de: T12
      Acceptance criteria: fixture succeeded com provider, model, tokens e `latency_ms` não nulos; show retorna `response_delivery_status`.
      Testes: `spec/requests/api/v1/accounts/scan_solo/ai_turns_spec.rb`
- [ ] T23 — Endpoint de opt-out do contato (CT-11, RF-63)
      Arquivos: `app/controllers/api/v1/accounts/scan_solo/contacts/opt_outs_controller.rb`, `app/views/api/v1/accounts/scan_solo/contacts/opt_outs/show.json.jbuilder`, `config/routes.rb`
      Mudança: `get/delete 'contacts/:contact_id/opt_out'` com `Current.account.contacts.find` (outra conta → 404); show para qualquer usuário; destroy autoriza `ContactOptOutPolicy#destroy?` e delega a `OptOut::ClearService`; resposta `{contact_id, opted_out}`.
      Cobre: RF-63, UI-15, CT-11
      Depende de: T05, T09
      Acceptance criteria: admin DELETE → 200 `{opted_out: false}` + 1 `contact.opt_out_cleared`; agente → 403, marcador inalterado; contato de outra conta → 404.
      Testes: `spec/requests/api/v1/accounts/scan_solo/contacts/opt_outs_spec.rb`
- [ ] T24 — StatusReport, endpoint de status e smoke (RF-58, RF-60, CT-07)
      Arquivos: `app/services/scan_solo/status_report.rb`, `app/controllers/api/v1/accounts/scan_solo/status_controller.rb`, `app/views/api/v1/accounts/scan_solo/status/show.json.jbuilder`, `lib/tasks/scansolo.rake`, `config/routes.rb`
      Mudança: `StatusReport` calcula GIT_SHA servido vs `EXPECTED_GIT_SHA`, migrations pendentes, 4 definições ativas, chave OpenAI presente (booleano), config publicada+habilitada com allowlist não vazia, inboxes da allowlist com `active_bot?`, cron `scan_solo_cadence_due_attempt_job` registrado, `Proposal::Integration.state`, último sync de templates por inbox WhatsApp; `GET /status` (admin) sem valores secretos; `scansolo:smoke[account_id]` imprime pass/fail e sai não-zero nomeando a falha.
      Cobre: RF-58, RF-60, RNF-04, CT-07
      Depende de: T03, T05, T06, T20
      Acceptance criteria: cada check forçado a falhar → saída não-zero com o nome; resposta só com booleanos/timestamps/contagens para credenciais; agente → 403.
      Testes: `spec/services/scan_solo/status_report_spec.rb`, `spec/requests/api/v1/accounts/scan_solo/status_spec.rb`, `spec/lib/tasks/scansolo_rake_spec.rb`

## Phase 4: Deploy, runbooks e frontend P0

Antes de implementar, leia:
1. `.spec/features/scansolo-production-complete/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-production-complete/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-production-complete/openapi.yaml` — CT-01 e control_state consumidos pelo FE (T30, T31)

Nunca editar arquivos de Nginx, TLS, certificados ou DNS; nunca executar `docker compose up` contra produção.

- [ ] T25 — Compose de produção, Dockerfile com GIT_SHA, imagens fixadas, `.env.example` (RF-52, RF-53, RF-54, RF-55)
      Arquivos: `docker-compose.production.yaml`, `docker-compose.scansolo.yaml`, `docker/Dockerfile`, `.dockerignore`, `.env.example`, `spec/lib/scansolo_production_compose_spec.rb`
      Mudança: `POSTGRES_PASSWORD=${POSTGRES_PASSWORD}`, remover `version:`, portas publicadas só `127.0.0.1:`, imagens com versão explícita (iguais às da VPS — HG-08); header do overlay só com `docker compose -f docker-compose.production.yaml -f docker-compose.scansolo.yaml`, `reverse-proxy`/`self-hosted-storage` só atrás de profiles nunca usados; Dockerfile `ARG GIT_SHA` + `RUN test -n "$GIT_SHA" && echo "$GIT_SHA" > /app/.git_sha` no lugar de `git rev-parse HEAD`; `.git` no `.dockerignore`; `.env.example` com todas as variáveis do compose e `RATE_LIMIT_SCANSOLO_*` vazias.
      Cobre: RF-52, RF-53, RF-54, RF-55, RNF-04
      Depende de: nenhuma
      Acceptance criteria: `docker compose -f docker-compose.production.yaml -f docker-compose.scansolo.yaml config --no-interpolate` mostra `${POSTGRES_PASSWORD}`, portas `127.0.0.1:`, nenhum `vite`/`mailhog`/`caddy`/`minio` sem profile, nenhum volume `./`, 0 imagens `:latest`/sem tag; Dockerfile sem `git rev-parse`; toda variável do compose vazia no `.env.example`.
      Testes: `spec/lib/scansolo_production_compose_spec.rb`
- [ ] T26 — Runbook de deploy e rotação de chave (RF-56, RF-57)
      Arquivos: `docs/architecture/SCANSOLO_DEPLOYMENT.md`, `spec/lib/scansolo_deployment_doc_spec.rb`
      Mudança: 9 passos ordenados copiáveis (diff VPS vs Git → `pg_dump` via profile `backup` + tamanho → build com `GIT_SHA` + novo `SCANSOLO_IMAGE_TAG` → migrate → `scansolo:load_cadence_definitions` → restart Rails → restart Sidekiq → `scansolo:smoke` → rollback com tag anterior + restart + restore); só o comando produção+overlay; restart de Rails e Sidekiq após salvar/rotacionar `CAPTAIN_OPEN_AI_API_KEY`; nota D-21 (setup pré-cutover com flag ligada e allowlist vazia); nenhum comando Nginx/certbot/DNS/`--profile reverse-proxy`. Atualizar asserts antigos do doc spec (comportamento substituído).
      Cobre: RF-56, RF-57
      Depende de: T20, T24, T25
      Acceptance criteria: doc spec encontra os 9 passos em ordem, 0 `-f docker-compose.yaml`, 0 comandos `nginx`/`certbot`/`--profile reverse-proxy`, o passo de restart após a chave e a nota da allowlist vazia.
      Testes: `spec/lib/scansolo_deployment_doc_spec.rb`
- [ ] T27 — Roteiro de teste controlado de go-live (RF-62)
      Arquivos: `docs/runbooks/SCANSOLO_GO_LIVE_TEST.md`, `spec/lib/scansolo_go_live_test_doc_spec.rb`
      Mudança: 12 critérios numerados (mensagem real chega; exatamente um turno; exatamente uma resposta; RAG usado; oportunidade criada; estágio correto; cadência coerente; resposta humana pausa a IA; devolver à IA funciona; nenhuma proposta mock; logs/correlation id; nenhum envio duplicado), cada um com "Ação", "Evidência" (query, endpoint ou tela) e "Passa se" binário; seção `Gates humanos` reservada para a Phase 6.
      Cobre: RF-62, RNF-03
      Depende de: T22, T24
      Acceptance criteria: doc spec encontra 12 critérios numerados, cada um com `Ação`, `Evidência` e `Passa se`.
      Testes: `spec/lib/scansolo_go_live_test_doc_spec.rb`
- [ ] T28 — FE: guard de rota por flag e layout com scroll (RF-51, UI-02)
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/index.js`, `app/javascript/dashboard/routes/dashboard/scansolo/components/ScanSoloPageLayout.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/agent/AgentCenter.vue`, `agent/TurnEvidenceViewer.vue`, `knowledge/KnowledgeCenter.vue`, `followups/FollowUps.vue`, `proposals/Proposals.vue`, `executions/Executions.vue`, `pipeline/KanbanBoard.vue`, `pipeline/OpportunityDetail.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/specs/routeGuard.spec.js`, `app/javascript/dashboard/routes/dashboard/scansolo/specs/ScanSoloPageLayout.spec.js`
      Mudança: `beforeEnter` lê `scansolo_enabled` da conta atual e redireciona ao dashboard antes de montar; `ScanSoloPageLayout.vue` (`<script setup>`, Tailwind `flex flex-col h-full min-h-0` + container interno `overflow-y-auto`, espelhando `components-next/captain/PageLayout.vue`) envolve a raiz de cada módulo; `Dashboard.vue` intocado.
      Cobre: RF-51, UI-02
      Depende de: nenhuma
      Acceptance criteria: flag off → redirect e 0 chamadas de API ScanSolo; toda rota ScanSolo renderiza dentro do container `overflow-y-auto` limitado; checagem manual em 1366×768 e 375×667 alcança último campo e salvar/publicar.
      Testes: `routeGuard.spec.js`, `ScanSoloPageLayout.spec.js`
- [ ] T29 — FE: chaves i18n sem raw keys + spec de completude (UI-03, RNF-10)
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/agent/AgentCenter.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/agent/agentCenterFields.js`, `app/javascript/dashboard/i18n/locale/en/scansolo.json`, `app/javascript/dashboard/routes/dashboard/scansolo/specs/i18nCompleteness.spec.js`
      Mudança: trocar `field.toUpperCase()` (`AgentCenter.vue:157,169,181`) por mapa estático campo→chave (`modelProvider → MODEL_PROVIDER`); adicionar chaves faltantes; spec carrega o `en/scansolo.json` real e verifica toda chave `SCANSOLO.*` referenciada pelos componentes ScanSolo.
      Cobre: UI-03, RNF-10
      Depende de: T28
      Acceptance criteria: 0 chaves faltantes; as 10 chaves de `GAP_ANALYSIS.md` Área 2 resolvem; nenhum `toUpperCase()` montando chave.
      Testes: `i18nCompleteness.spec.js`, `agent/specs/AgentCenter.spec.js`
- [ ] T30 — FE: seções do Agent Center + Canais com allowlist (UI-04)
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/agent/AgentCenter.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/agent/agentCenterFields.js`, `app/javascript/dashboard/store/scansolo/aiAgentConfig.js`, `app/javascript/dashboard/i18n/locale/en/scansolo.json`, `app/javascript/dashboard/routes/dashboard/scansolo/agent/specs/AgentCenter.spec.js`
      Mudança: 9 seções Identidade, Modelo, Comportamento, Qualificação, Segurança, Handoff, Horário, Proposta, Canais; Canais = multi-select de inboxes da conta por nome ligado a `allowed_inbox_ids`; store envia/recebe os novos campos CT-01.
      Cobre: UI-04, RF-03
      Depende de: T04, T29
      Acceptance criteria: spec encontra os 9 títulos e o multi-select listando nomes (sem ids crus); salvar envia `allowed_inbox_ids`.
      Testes: `agent/specs/AgentCenter.spec.js`
- [ ] T31 — FE: montar HandoffControlBanner na conversa (UI-01)
      Arquivos: `app/javascript/dashboard/components/widgets/conversation/ConversationBox.vue`, `app/javascript/dashboard/components-next/conversation/HandoffControlBanner.vue`, `app/javascript/dashboard/api/scansoloHandoff.js`, `app/javascript/dashboard/i18n/locale/en/scansolo.json`, `app/javascript/dashboard/components-next/conversation/specs/HandoffControlBanner.spec.js`
      Mudança: montar abaixo do `ConversationHeader` quando a conta é `scansolo_enabled` e o inbox está em `allowed_inbox_ids` publicado; mostra estado e uma única ação (takeover em `ai_active`; devolver em `human_active`/`awaiting_human`), habilitada só para admin ou assignee (espelha `HandoffPolicy`); refaz a leitura após cada ação e quando surge nova mensagem outgoing não-privada de usuário.
      Cobre: UI-01, RF-18
      Depende de: T11, T29
      Acceptance criteria: spec com i18n real mostra rótulo do estado e a ação correta por estado; após resposta de agente o banner mostra `human_active` sem reload.
      Testes: `HandoffControlBanner.spec.js`

## Phase 5: P1 — Make, auditoria, rate limit, execuções, UX

Antes de implementar, leia:
1. `.spec/features/scansolo-production-complete/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-production-complete/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-production-complete/asyncapi.yaml` — CT-05 e CT-06 (T32, T33)
4. `.spec/features/scansolo-production-complete/openapi.yaml` — CT-03, CT-04, CT-10, CT-11 (T34, T37, T41–T45)

- [ ] T32 — MakeProvider completo e mapeamento de erros (RF-37, CT-05)
      Arquivos: `app/services/scan_solo/proposal/make_provider.rb`, `app/services/scan_solo/make/outbound_request_service.rb`
      Mudança: payload conforme `asyncapi.yaml` (`action` `proposal.generate|proposal.send`, account/opportunity/version ids, `qualification` dos `required_qualification_fields`, `requested_by_user_id` anulável, `requested_at`), correlation = correlation da versão; `MakeRequest` antes do HTTP; `Net::OpenTimeout`/`Net::ReadTimeout`/`Timeout::Error` → `timeout`, erros de conexão/DNS → `network_error`, HTTP 5xx → `provider_unavailable`; versão `failed` com a razão sem propagar exceção.
      Cobre: RF-37, CT-05
      Depende de: T06
      Acceptance criteria: WebMock sucesso → `MakeRequest` com a correlation da versão; cada uma das 3 classes de erro → versão `failed` com a razão mapeada.
      Testes: `spec/services/scan_solo/proposal/make_provider_spec.rb`, `spec/services/scan_solo/make/outbound_request_service_spec.rb`
- [ ] T33 — Callback Make aplicado ao ProposalVersion (RF-38, RF-39, CT-06)
      Arquivos: `app/controllers/webhooks/scan_solo/make_controller.rb`, `app/services/scan_solo/make/callback_application_service.rb`, `app/services/scan_solo/proposal/callback_handler.rb`
      Mudança: controller só verifica e delega a `CallbackApplicationService` (registra `MakeCallback(applied: true)`, atualiza `MakeRequest`, chama `CallbackHandler.apply_generate_result!`/`apply_send_result!` numa transação); `already_processed?` → `MakeCallback.applied.exists?`; rejeições `applied: false` não reservam o id; send → template nativo via T16 (`origin: 'proposal'`) → reconciliador T19.
      Cobre: RF-38, RF-39, CT-06
      Depende de: T19, T32
      Acceptance criteria: callback generate assinado → versão `generated` com o valor do callback; duplicado → 200, 0 mudanças; schema inválido (422) seguido de válido com mesma correlation → 200 aplicado; send → 1 mensagem de template e, após aceite, `proposta_enviada`; assinatura inválida → 401 sem persistir.
      Testes: `spec/requests/webhooks/scan_solo/make_spec.rb`, `spec/services/scan_solo/make/callback_application_service_spec.rb`
- [ ] T34 — Retry, dead letter, reprocessamento e campos de proposta (RF-40, RF-42, CT-04)
      Arquivos: `app/controllers/api/v1/accounts/scan_solo/proposals_controller.rb`, `app/services/scan_solo/proposal/retry_policy.rb`, `app/views/api/v1/accounts/scan_solo/proposals/_proposal.json.jbuilder`, `app/views/api/v1/accounts/scan_solo/proposals/_proposal_version.json.jbuilder`, `app/views/api/v1/accounts/scan_solo/proposals/retry.json.jbuilder`, `config/routes.rb`
      Mudança: rota `post :retry`; validação de `proposal_version_id` + `confirm_reprocess` na borda; `authorize :retry?`; `RetryPolicy` (não-retentável → 422 `UnsafeRetryError`; `retry_count >= 3` sem `confirm_reprocess: true` → 422; nova correlation; incrementa `retry_count`); representações ganham `failure_reason`, `correlation_id`, `retry_count`, `dead_letter`, `integration_state`, `owner_id`.
      Cobre: RF-40, RF-42, CT-04, UI-13
      Depende de: T32
      Acceptance criteria: 3 retries falhos → item nos dead letters de executions; 4º retry simples → 422; reprocess com confirmação → novo `MakeRequest`; versão falha na API com `failure_reason` + `correlation_id`.
      Testes: `spec/requests/api/v1/accounts/scan_solo/proposals_spec.rb`, `spec/services/scan_solo/proposal/retry_policy_spec.rb`
- [ ] T35 — Eventos de auditoria administrativos (RF-50)
      Arquivos: `app/services/scan_solo/ai_agent/draft_update_service.rb`, `app/services/scan_solo/ai_agent/publish_service.rb`, `app/services/scan_solo/knowledge/source_write_service.rb`, `app/services/scan_solo/knowledge/reindex_service.rb`, `app/services/scan_solo/messaging/template_mapping_upsert_service.rb`, `app/services/scan_solo/proposal/retry_policy.rb`, `app/controllers/api/v1/accounts/scan_solo/ai_agent_configs_controller.rb`, `app/controllers/api/v1/accounts/scan_solo/knowledge/sources_controller.rb`
      Mudança: mover escritas restantes dos controllers (draft `update!`, create/update/destroy de knowledge) para services e gravar 1 `AuditLogger.record!` por evento: draft atualizado (inclui mudança de `opt_out_keywords`), publicado, knowledge criado/atualizado/removido/reindexado, template mapping atualizado, retry/reprocess solicitado; ator, sujeito, correlation, sem segredos.
      Cobre: RF-50, RNF-04
      Depende de: T17, T21, T34
      Acceptance criteria: um spec por evento listado com exatamente 1 linha de auditoria com ator, sujeito, ação e correlation, sem valor secreto.
      Testes: `spec/services/scan_solo/ai_agent/draft_update_service_spec.rb`, `spec/services/scan_solo/knowledge/source_write_service_spec.rb`, `spec/integration/scan_solo/admin_audit_events_spec.rb`
- [ ] T36 — Rate limits por conta e teto de top_k (RF-49, RNF-06)
      Arquivos: `config/initializers/rack_attack.rb`, `app/controllers/api/v1/accounts/scan_solo/knowledge/retrieval_tests_controller.rb`, `.env.example`
      Mudança: throttles por account id do path: `scan_solo/knowledge_writes` (`RATE_LIMIT_SCANSOLO_KNOWLEDGE_WRITES`, 20/min), `scan_solo/retrieval_tests` (30/min), `scan_solo/publish` (10/min), todos ENV-overridable; `top_k > 20` → 422 na borda.
      Cobre: RF-49, RNF-06
      Depende de: T25
      Acceptance criteria: requisição N+1 na janela → 429; override por ENV altera o limite; `top_k: 21` → 422.
      Testes: `spec/requests/api/v1/accounts/scan_solo/rate_limits_spec.rb`, `spec/requests/api/v1/accounts/scan_solo/knowledge/retrieval_tests_spec.rb`
- [ ] T37 — API de execuções enriquecida (RF-61, CT-10)
      Arquivos: `app/controllers/api/v1/accounts/scan_solo/executions_controller.rb`, `app/services/scan_solo/executions_feed_query.rb`, `app/views/api/v1/accounts/scan_solo/executions/index.json.jbuilder`
      Mudança: controller delega a `ExecutionsFeedQuery`: attempts com `message_id`, `last_block_reason`, `last_checked_at`, `external_error`; `template_availability`; `handoff_events` (explicit/implicit/ai_action); callbacks rejeitados com razão; dead letters; `recent_errors` (≤ 100: turnos falhos, attempts falhos, callbacks rejeitados).
      Cobre: RF-61, CT-10
      Depende de: T17, T19, T33
      Acceptance criteria: fixtures de cada tipo aparecem com os campos listados; `recent_errors.length <= 100`.
      Testes: `spec/requests/api/v1/accounts/scan_solo/executions_spec.rb`, `spec/services/scan_solo/executions_feed_query_spec.rb`
- [ ] T38 — FE: primitivas compartilhadas e chaves i18n P1
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/composables/useScanSoloRole.js`, `app/javascript/dashboard/routes/dashboard/scansolo/components/TechnicalDetails.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/components/ScanSoloListState.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/scansoloLabels.js`, `app/javascript/dashboard/i18n/locale/en/scansolo.json`, `app/javascript/dashboard/routes/dashboard/scansolo/components/specs/TechnicalDetails.spec.js`
      Mudança: `useScanSoloRole` (`isAdministrator`, `isOwner`); `TechnicalDetails.vue` colapsado só para admins; `ScanSoloListState.vue` (loading/empty/error); mapas enum→rótulo pt-BR; todas as chaves de copy de T39–T45 adicionadas aqui de uma vez.
      Cobre: UI-09, UI-10, RNF-10
      Depende de: T29
      Acceptance criteria: `TechnicalDetails` não renderiza para agentes e renderiza colapsado para admins; spec de completude i18n continua verde.
      Testes: `TechnicalDetails.spec.js`, `i18nCompleteness.spec.js`
- [ ] T39 — FE: Agent Center P1 — feedback, alterações não salvas, aprovação, modelos, opt-out keywords (UI-05, UI-06, UI-07, UI-08, UI-09, UI-14)
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/agent/AgentCenter.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/agent/agentCenterFields.js`, `app/javascript/dashboard/store/scansolo/aiAgentConfig.js`, `app/javascript/dashboard/routes/dashboard/scansolo/agent/specs/AgentCenter.spec.js`
      Mudança: salvar/publicar desabilitam os dois botões + spinner até a resposta, toast `useAlert` de sucesso/erro com mensagem do servidor, confirmação de publicar mantida; `onBeforeRouteLeave` + `beforeunload` com formulário sujo; toggle `require_proposal_approval` na seção Proposta; selects de provider/modelo de `available_models`; UI-14: lista editável de palavras-chave de opt-out na seção **Segurança** (defaults PARAR, SAIR, STOP), somente leitura para não-admin; estados de loading/erro.
      Cobre: UI-05, UI-06, UI-07, UI-08, UI-09, UI-14
      Depende de: T30, T38
      Acceptance criteria: promise pendente → botões desabilitados; resolvida → toast de sucesso; rejeitada → toast de erro; formulário sujo + troca de rota → confirmação; toggle persiste; select lista os 4 modelos; campo de keywords mostra defaults e nova entrada vai no payload do draft; agente vê o campo somente leitura.
      Testes: `agent/specs/AgentCenter.spec.js`
- [ ] T40 — FE: Conhecimento — estados, confirmação, ids técnicos (UI-09, UI-10, UI-11)
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/knowledge/KnowledgeCenter.vue`, `app/javascript/dashboard/store/scansolo/knowledgeSources.js`, `app/javascript/dashboard/routes/dashboard/scansolo/knowledge/specs/KnowledgeCenter.spec.js`
      Mudança: badge de status, `chunk_count`, `indexed_at` (relativo + absoluto no hover via `timeHelper`), último erro em `failed`; confirmação antes de excluir; loading/empty/error; controles de escrita ocultos para agentes; ids técnicos em `TechnicalDetails`.
      Cobre: UI-09, UI-10, UI-11
      Depende de: T21, T38
      Acceptance criteria: fixture de cada status mostra o badge e, em `failed`, o erro; excluir exige confirmação antes da chamada; agente vê 0 ids técnicos/strings ISO.
      Testes: `knowledge/specs/KnowledgeCenter.spec.js`
- [ ] T41 — FE: Follow-ups + painel de templates (UI-09, UI-10, UI-12)
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/followups/FollowUps.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/followups/TemplatesPanel.vue`, `app/javascript/dashboard/api/scansoloCadenceTemplates.js`, `app/javascript/dashboard/store/scansolo/cadenceTemplates.js`, `app/javascript/dashboard/routes/dashboard/scansolo/followups/specs/TemplatesPanel.spec.js`, `app/javascript/dashboard/routes/dashboard/scansolo/followups/specs/FollowUps.spec.js`
      Mudança: painel por estágio/passo e envio de proposta com nome, idioma, params, disponibilidade, status Meta, razão de bloqueio e último sync; edição só para admin (PUT CT-03, toast com mensagem 422); confirmação ao cancelar follow-up; loading/erro; timestamps nativos.
      Cobre: UI-09, UI-10, UI-12
      Depende de: T17, T38
      Acceptance criteria: fixture com um template disponível e um `PAUSED` mostra as duas linhas com disponibilidade/razão corretas; agente sem controle de edição; cancelar exige confirmação.
      Testes: `TemplatesPanel.spec.js`, `FollowUps.spec.js`
- [ ] T42 — FE: Propostas por papel e integração bloqueada (UI-09, UI-10, UI-13)
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/proposals/Proposals.vue`, `app/javascript/dashboard/api/scansoloProposals.js`, `app/javascript/dashboard/store/scansolo/proposals.js`, `app/javascript/dashboard/routes/dashboard/scansolo/proposals/specs/Proposals.spec.js`
      Mudança: `integration_state: blocked` → gerar/enviar/retry desabilitados + explicação pt-BR; `failure_reason` visível; botões por papel: gerar qualquer, aprovar admin, enviar admin ou owner (`owner_id`), retry/reprocess admin (reprocess envia `confirm_reprocess: true` após confirmação); confirmação antes de enviar.
      Cobre: UI-09, UI-10, UI-13
      Depende de: T34, T38
      Acceptance criteria: bloqueado → botões desabilitados + explicação; versão falha → razão visível; agente não-owner → só gerar; agente owner → gerar + enviar; admin → gerar, aprovar, enviar e retry; enviar exige confirmação.
      Testes: `proposals/specs/Proposals.spec.js`
- [ ] T43 — FE: Execuções (UI-09, UI-10, RF-61)
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/executions/Executions.vue`, `app/javascript/dashboard/store/scansolo/executions.js`, `app/javascript/dashboard/routes/dashboard/scansolo/executions/specs/Executions.spec.js`
      Mudança: renderizar attempts com resultado/razão/evidência de entrega, disponibilidade de templates, callbacks aplicados/rejeitados, dead letters (reprocess via retry CT-04 com confirmação, só admin), eventos de handoff explicit/implicit, erros recentes; loading/erro; ids em `TechnicalDetails`.
      Cobre: UI-09, UI-10, RF-61
      Depende de: T37, T38, T42
      Acceptance criteria: fixture de cada tipo do feed renderiza; reprocess exige confirmação e fica oculto para agentes; agente vê 0 correlation ids.
      Testes: `executions/specs/Executions.spec.js`
- [ ] T44 — FE: Kanban, detalhe da oportunidade e evidência do turno (UI-09, UI-10)
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/KanbanBoard.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/OpportunityDetail.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/agent/TurnEvidenceViewer.vue`, `app/javascript/dashboard/store/scansolo/aiTurns.js`, `pipeline/specs/KanbanBoard.spec.js`, `pipeline/specs/OpportunityDetail.spec.js`, `agent/specs/TurnEvidenceViewer.spec.js`
      Mudança: loading/empty/error; timestamps relativo+absoluto; enums com rótulos pt-BR; `ownerId`/`sourceId`/correlation/JSON cru (`context_snapshot`) só no `TechnicalDetails` admin; viewer mostra títulos/scores de `knowledge_evidence`, `latency_ms`, `response_delivery_status`.
      Cobre: UI-09, UI-10, RF-59
      Depende de: T22, T38
      Acceptance criteria: specs com papel agente encontram 0 correlation ids/strings ISO no Kanban e na evidência do turno; spec admin os encontra no bloco colapsado.
      Testes: `KanbanBoard.spec.js`, `OpportunityDetail.spec.js`, `TurnEvidenceViewer.spec.js`
- [ ] T45 — FE: opt-out no painel do contato (UI-15)
      Arquivos: `app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/components/ContactOptOutCard.vue`, `app/javascript/dashboard/api/scansoloContacts.js`, `app/javascript/dashboard/routes/dashboard/scansolo/components/specs/ContactOptOutCard.spec.js`
      Mudança: card montado em `ContactPanel.vue` só para contas `scansolo_enabled`; lê o estado (`GET contacts/:id/opt_out`), mostra a todos; para admin com contato opted-out, "remover opt-out" → confirmação → `DELETE` (CT-11) → releitura + toast.
      Cobre: UI-15
      Depende de: T23, T38
      Acceptance criteria: admin + opted-out → ação visível; confirmar → 1 chamada DELETE e estado não-opted-out após a resposta; agente → estado visível, 0 controles; contato não opted-out → sem ação; copy do `en/scansolo.json` real.
      Testes: `ContactOptOutCard.spec.js`
- [ ] T46 — Gate de regressão: baseline de specs, isolamento, segredos (RNF-04, RNF-07, RNF-09)
      Arquivos: `spec/lib/scansolo_secret_hygiene_spec.rb`
      Mudança: spec verifica `.env.example` com valores vazios, jbuilders `scan_solo` sem atributo de credencial e cobertura do `PromptRedactor`; rodar as suítes ScanSolo e comparar contagem de exemplos com o baseline do commit `4af19b0bb` (`bundle exec rspec spec/**/scan_solo spec/lib/scansolo_* --dry-run` e `pnpm test` dos specs ScanSolo), excluindo exemplos reescritos por comportamento substituído.
      Cobre: RNF-04, RNF-07, RNF-09
      Depende de: T01–T45
      Acceptance criteria: spec de higiene verde; `spec/lib/scansolo_no_enterprise_dependency_spec.rb` verde; contagens Ruby e FE ≥ baseline; `bundle exec rubocop` e `pnpm eslint` limpos nos arquivos alterados.
      Testes: `spec/lib/scansolo_secret_hygiene_spec.rb` + suítes ScanSolo completas

## Phase 6: HUMAN GATES — checkpoints documentados (não bloqueiam o restante)

Antes de implementar, leia:
1. `.spec/features/scansolo-production-complete/SPEC.md` — tabela "Human Gates" HG-01..HG-11
2. `.spec/features/scansolo-production-complete/PLAN.md` — decomposição completa, dependências e riscos

Cada item abaixo apenas DOCUMENTA um checkpoint verificável em `docs/runbooks/SCANSOLO_GO_LIVE_TEST.md` (Dono, Desbloqueia, Verificação via `scansolo:smoke` / `GET /scan_solo/status` / tela, e uma linha "Assinatura" desmarcada). A ação externa (Meta, Make, SMTP, LEXUS, credenciais, diff da VPS, sign-off) é feita por humanos fora do ralph; nenhum agente executa a ação protegida e nenhuma tarefa das fases 1–5 depende destes itens.

- [ ] T47 — Checkpoint HG-01, HG-06, HG-09: ativação da IA (Meta, allowlist + Captain inativo, chave OpenAI)
      Arquivos: `docs/runbooks/SCANSOLO_GO_LIVE_TEST.md`, `spec/lib/scansolo_go_live_test_doc_spec.rb`
      Mudança: entradas HG-01 (Admin Meta: credenciais + App Secret no canal; verificação: webhook assinado recebido), HG-06 (Produto + Ops: allowlist; verificação: `status.agent.allowed_inbox_ids` não vazio e `status.inbox_conflicts == []`), HG-09 (Ops: chave OpenAI + restart; verificação: `status.llm_key_configured == true` e um turno `succeeded`).
      Cobre: HG-01, HG-06, HG-09
      Depende de: T27
      Acceptance criteria: doc spec encontra HG-01, HG-06, HG-09 cada um com `Dono`, `Desbloqueia`, `Verificação`, `Assinatura`.
      Testes: `spec/lib/scansolo_go_live_test_doc_spec.rb`
- [ ] T48 — Checkpoint HG-02, HG-03: templates Meta e integração Make
      Arquivos: `docs/runbooks/SCANSOLO_GO_LIVE_TEST.md`, `spec/lib/scansolo_go_live_test_doc_spec.rb`
      Mudança: HG-02 (Produto + Admin Meta: templates aprovados e mapeados; verificação: `GET /scan_solo/cadence_templates` sem linha `blocked`); HG-03 (Dono do Make + Ops: 3 credenciais `scan_solo.make.*` + master key na VPS + contrato de payload/preço; verificação: `status.proposal_integration == "configured"`; decide a nomenclatura de `action`).
      Cobre: HG-02, HG-03
      Depende de: T47
      Acceptance criteria: doc spec encontra HG-02 e HG-03 com os 4 campos.
      Testes: `spec/lib/scansolo_go_live_test_doc_spec.rb`
- [ ] T49 — Checkpoint HG-04, HG-05, HG-07, HG-08: SMTP, LEXUS, papéis, diff da VPS
      Arquivos: `docs/runbooks/SCANSOLO_GO_LIVE_TEST.md`, `spec/lib/scansolo_go_live_test_doc_spec.rb`
      Mudança: HG-04 (Ops: SMTP no `.env` da VPS; verificação: convite entregue); HG-05 (Dono LEXUS + Ops: dono único do webhook Meta; verificação: checklist de `docs/runbooks/PRODUCTION_CUTOVER.md`; kill switch `scansolo_enabled`); HG-07 (Produto/Gestão: administradores definidos); HG-08 (Ops: diff compose/.env e tags de imagem da VPS vs Git antes do deploy — passo 1 do runbook).
      Cobre: HG-04, HG-05, HG-07, HG-08
      Depende de: T48
      Acceptance criteria: doc spec encontra HG-04, HG-05, HG-07, HG-08 com os 4 campos.
      Testes: `spec/lib/scansolo_go_live_test_doc_spec.rb`
- [ ] T50 — Checkpoint HG-10, HG-11: sign-off do go-live e escopo PDF/crawler
      Arquivos: `docs/runbooks/SCANSOLO_GO_LIVE_TEST.md`, `spec/lib/scansolo_go_live_test_doc_spec.rb`
      Mudança: HG-10 (Produto + Ops: executar os 12 critérios e assinar; produção declarada só com todos "Passa"); HG-11 (Produto + Dev: escopo/tecnologia de PDF e crawler; RF-47 não implementado até a decisão e, quando implementado, só via `SafeFetch` + `ssrf_filter` com allowlist de domínio).
      Cobre: HG-10, HG-11
      Depende de: T49
      Acceptance criteria: doc spec encontra HG-10 e HG-11 com os 4 campos e o texto da restrição SSRF do RF-47.
      Testes: `spec/lib/scansolo_go_live_test_doc_spec.rb`
