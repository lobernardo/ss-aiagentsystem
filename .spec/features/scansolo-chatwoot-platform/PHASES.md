# Phases: scansolo-chatwoot-platform

Gerado por /plan a partir de PLAN.md — view executável para `./ralph.sh .spec/features/scansolo-chatwoot-platform/PHASES.md`.

## Phase 1: Foundation & platform shell

Antes de implementar, leia:
1. `.spec/features/scansolo-chatwoot-platform/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-chatwoot-platform/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T01 — Feature flag + ScanSolo:: namespace scaffold
      Arquivos: `app/models/account.rb`, `app/models/scan_solo/.keep`, `app/services/scan_solo/.keep`, `app/jobs/scan_solo/.keep`, `app/policies/scan_solo/.keep`, `db/migrate/XXXXXXXXXXXXXX_add_scansolo_enabled_flag_to_accounts.rb`
      Mudança: adicionar `scansolo_enabled` como novo bit aditivo `FlagShihTzu` em `Account` e criar o scaffold vazio do namespace `ScanSolo::`.
      Cobre: RF-95
      Depende de: nenhuma
      Acceptance criteria: `scansolo_enabled?` existe em `Account`, default `false`, não altera nenhum bit pré-existente.
      Testes: `spec/models/account_spec.rb` — novo contexto assertando default `false` e toggle sem afetar flags existentes.
- [ ] T02 — Routes namespace + base API controller/policy
      Arquivos: `config/routes.rb`, `app/controllers/api/v1/accounts/scan_solo/base_controller.rb`
      Mudança: registrar namespace `api/v1/accounts/:account_id/scan_solo/*` e `BaseController` que retorna 404 quando `scansolo_enabled?` é falso.
      Cobre: RF-95, RF-96
      Depende de: T01
      Acceptance criteria: requisição contra conta sem a flag retorna 404; conta habilitada passa para autenticação nativa.
      Testes: `spec/controllers/api/v1/accounts/scan_solo/base_controller_spec.rb`
- [ ] T03 — i18n scaffold para namespace ScanSolo
      Arquivos: `app/javascript/dashboard/i18n/locale/en/scansolo.json`, `app/javascript/dashboard/i18n/locale/en/index.js`
      Mudança: criar namespace `en.json` do ScanSolo e registrá-lo no índice de locales.
      Cobre: RF-02, RNF-08
      Depende de: nenhuma
      Acceptance criteria: namespace carrega via mecanismo de i18n existente; `pnpm eslint` sinaliza string solta futura sob `dashboard/routes/dashboard/scansolo/`.
      Testes: `app/javascript/dashboard/i18n/locale/en/specs/scansolo.spec.js`
- [ ] T04 — Branding & hostname hygiene verification
      Arquivos: `spec/lib/scansolo_branding_spec.rb`, `.env.example`
      Mudança: spec garantindo branding só via `config/installation_config.yml` e busca no repositório por `scansolo.com.br` fora de config/docs.
      Cobre: RF-03, RF-04
      Depende de: nenhuma
      Acceptance criteria: busca por `scansolo.com.br` em `app/`, `lib/`, `config/routes.rb` retorna zero matches; branding muda só via config.
      Testes: `spec/lib/scansolo_branding_spec.rb`
- [ ] T05 — Dashboard shell: navegação dos 11 módulos
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/index.js`, `app/javascript/dashboard/components/layout/sidebarComponents/PrimaryNavItems.js`
      Mudança: registrar os 11 módulos exigidos como entradas navegáveis; 5 são stubs novos do ScanSolo (Pipeline, Agente de IA, Conhecimento, Follow-ups, Propostas, Execuções e auditoria).
      Cobre: RF-01
      Depende de: T02, T03
      Acceptance criteria: para conta `scansolo_enabled`, todas as 11 entradas renderizam e roteiam sem reload completo.
      Testes: `tests/playwright/scansolo/navigation.spec.ts`

## Phase 2: Shared core models

Antes de implementar, leia:
1. `.spec/features/scansolo-chatwoot-platform/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-chatwoot-platform/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T06 — Migration: scan_solo_conversation_extensions + scan_solo_audit_events
      Arquivos: `db/migrate/XXXXXXXXXXXXXX_create_scan_solo_conversation_extensions.rb`, `db/migrate/XXXXXXXXXXXXXX_create_scan_solo_audit_events.rb`
      Mudança: migrations aditivas puras `create_table` para controle de estado de IA por conversa e eventos de auditoria imutáveis.
      Cobre: RF-95, RNF-04
      Depende de: T01
      Acceptance criteria: ambas migrations contêm apenas `create_table`, sem `remove_column`/`change_column` em tabelas pré-existentes.
      Testes: `spec/db/scansolo_migrations_spec.rb`
- [ ] T07 — Model: ScanSolo::ConversationExtension
      Arquivos: `app/models/scan_solo/conversation_extension.rb`
      Mudança: `belongs_to :conversation`; enum `ai_control_state` com `ai_active, handoff_requested, awaiting_human, human_active, paused, closed`.
      Cobre: RF-50
      Depende de: T06
      Acceptance criteria: toda conversa resolve um estado de controle; cada valor do enum tem teste de transição associado.
      Testes: `spec/models/scan_solo/conversation_extension_spec.rb`
- [ ] T08 — Model/service: ScanSolo::AuditEvent + AuditLogger
      Arquivos: `app/models/scan_solo/audit_event.rb`, `app/services/scan_solo/audit_logger.rb`
      Mudança: model imutável de auditoria (sem update/destroy) e serviço `AuditLogger.record!` usado por todas as tarefas de efeito colateral subsequentes.
      Cobre: RNF-02
      Depende de: T06
      Acceptance criteria: `record!` persiste exatamente uma linha; `update`/`destroy` em `AuditEvent` existente levanta erro.
      Testes: `spec/services/scan_solo/audit_logger_spec.rb`
- [ ] T09 — Policy base: ScanSolo::ApplicationPolicy
      Arquivos: `app/policies/scan_solo/application_policy.rb`
      Mudança: policy Pundit base do namespace `ScanSolo::` com default `false` (fail-closed).
      Cobre: RF-89
      Depende de: T02
      Acceptance criteria: contexto de usuário não autorizado/ambíguo é negado por padrão.
      Testes: `spec/policies/scan_solo/application_policy_spec.rb`

## Phase 3: Pipeline / Kanban

Antes de implementar, leia:
1. `.spec/features/scansolo-chatwoot-platform/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-chatwoot-platform/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T10 — Migration: scan_solo_pipeline_opportunities + scan_solo_pipeline_stage_events
      Arquivos: `db/migrate/XXXXXXXXXXXXXX_create_scan_solo_pipeline_opportunities.rb`, `db/migrate/XXXXXXXXXXXXXX_create_scan_solo_pipeline_stage_events.rb`
      Mudança: tabelas aditivas para oportunidades de pipeline e histórico imutável de estágio.
      Cobre: RF-05, RF-06, RF-07
      Depende de: T01
      Acceptance criteria: migrations puramente aditivas (assertion estendida em `scansolo_migrations_spec.rb`).
      Testes: `spec/db/scansolo_migrations_spec.rb`
- [ ] T11 — Model: PipelineOpportunity + StageEvent
      Arquivos: `app/models/scan_solo/pipeline_opportunity.rb`, `app/models/scan_solo/pipeline_stage_event.rb`
      Mudança: enum `stage` restrito às 8 fases na ordem definida; leitura de stage só na própria coluna, independente de labels/custom attributes.
      Cobre: RF-05, RF-06
      Depende de: T10
      Acceptance criteria: persistir stage fora do vocabulário levanta erro de validação (422); alterar só labels/custom attributes não muda `stage`.
      Testes: `spec/models/scan_solo/pipeline_opportunity_spec.rb`
- [ ] T12 — Service: ScanSolo::Pipeline::StageTransitionService
      Arquivos: `app/services/scan_solo/pipeline/stage_transition_service.rb`
      Mudança: serviço determinístico de transição; cria exatamente um `PipelineStageEvent` por transição; rejeita transição para `negociacao` fora de ação autorizada explícita; trata `ganho`/`perdido` como terminais.
      Cobre: RF-07, RF-09, RF-18, RF-19
      Depende de: T08, T09, T11
      Acceptance criteria: transição rejeitada não altera a coluna no DB; tentativa não autorizada de `negociacao` é rejeitada; transição a partir de `ganho`/`perdido` é rejeitada.
      Testes: `spec/services/scan_solo/pipeline/stage_transition_service_spec.rb`
- [ ] T13 — Controller/routes: opportunities CRUD + stage transitions (CT-01)
      Arquivos: `config/routes.rb`, `app/controllers/api/v1/accounts/scan_solo/pipeline_opportunities_controller.rb`, `app/policies/scan_solo/pipeline_opportunity_policy.rb`
      Mudança: `GET`/`PATCH` de oportunidade (reatribuição de owner) e `POST .../stage_transitions` implementando CT-01, idempotente por `(opportunity_id, target_stage, actor)`.
      Cobre: CT-01, RF-08, RF-09, RF-10, RF-11
      Depende de: T02, T12
      Acceptance criteria: card só muda após confirmação do servidor; requisição rejeitada retorna 4xx e stage permanece; reatribuição de owner persiste.
      Testes: `spec/requests/api/v1/accounts/scan_solo/pipeline_opportunities_spec.rb`
- [ ] T14 — Stale indicator + filtros de Kanban/lista
      Arquivos: `app/services/scan_solo/pipeline/opportunity_query.rb`, `config/initializers/scansolo_constants.rb`
      Mudança: query object calculando indicador de inatividade com constante fixa de 48h e filtros por stage/owner/stale.
      Cobre: RF-12, RF-13
      Depende de: T11
      Acceptance criteria: oportunidade com 48h exatas é sinalizada; um segundo antes não; cada filtro reduz o conjunto no nível de query.
      Testes: `spec/services/scan_solo/pipeline/opportunity_query_spec.rb`
- [ ] T15 — Regra determinística: Novo Lead → Em Contato
      Arquivos: `app/services/scan_solo/conversation_listener.rb`, `app/services/scan_solo/pipeline/inbound_message_transition_rule.rb`
      Mudança: mensagem inbound real sem interação qualificadora prévia transiciona oportunidade `novo_lead` para `em_contato` exatamente uma vez.
      Cobre: RF-14
      Depende de: T12
      Acceptance criteria: uma mensagem fake move a oportunidade uma vez; segunda mensagem não retrigger.
      Testes: `spec/services/scan_solo/pipeline/inbound_message_transition_rule_spec.rb`
- [ ] T16 — Frontend: Kanban board (UI-01)
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/KanbanBoard.vue`, `app/javascript/dashboard/store/scansolo/pipelineOpportunities.js`
      Mudança: drag-and-drop agrupado por stage; card só move após confirmação do servidor; renderiza stage/owner/última interação/próximo follow-up/stale.
      Cobre: UI-01, RF-08, RF-09, RF-11
      Depende de: T05, T13, T14, T50
      Acceptance criteria: card reverte em resposta 4xx simulada; todos os cinco dados renderizam para oportunidade seedada.
      Testes: `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/specs/KanbanBoard.spec.js`
- [ ] T17 — Frontend: opportunity detail view (UI-02)
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/OpportunityDetail.vue`
      Mudança: lista cronológica de histórico de estágio, contato relacionado e link da conversa relacionada.
      Cobre: UI-02
      Depende de: T13
      Acceptance criteria: lista de histórico corresponde aos registros `PipelineStageEvent` seedados.
      Testes: `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/specs/OpportunityDetail.spec.js`

## Phase 4: AI Agent Center

Antes de implementar, leia:
1. `.spec/features/scansolo-chatwoot-platform/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-chatwoot-platform/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-chatwoot-platform/openapi.yaml` — contrato CT-02 implementado em T22

- [ ] T18 — Migration: scan_solo_ai_agent_configs
      Arquivos: `db/migrate/XXXXXXXXXXXXXX_create_scan_solo_ai_agent_configs.rb`
      Mudança: tabela aditiva com todos os campos RF-20 mais `status` (draft/published) e referência de versão publicada.
      Cobre: RF-20, RF-22
      Depende de: T01
      Acceptance criteria: migration puramente aditiva.
      Testes: `spec/db/scansolo_migrations_spec.rb`
- [ ] T19 — Model + serviço de versionamento: draft/publish
      Arquivos: `app/models/scan_solo/ai_agent_config.rb`, `app/services/scan_solo/ai_agent/publish_service.rb`
      Mudança: edição de draft nunca afeta conversa ao vivo; `PublishService#call` troca atomicamente a versão publicada ativa.
      Cobre: RF-20, RF-22
      Depende de: T18
      Acceptance criteria: editar draft não muda comportamento de turno em andamento; publish é atômico.
      Testes: `spec/services/scan_solo/ai_agent/publish_service_spec.rb`
- [ ] T20 — Provider resolution via lib/llm::FeatureRouter
      Arquivos: `app/services/scan_solo/ai_agent/model_resolver.rb`
      Mudança: resolução de modelo/provider exclusivamente via `Llm::FeatureRouter`; verificação de ausência de dependência de `Captain::`.
      Cobre: RF-21, RF-26
      Depende de: T19
      Acceptance criteria: resolução rastreável ao `Llm::FeatureRouter`; nenhum arquivo sob `app/**/scan_solo/` referencia `Captain::`.
      Testes: `spec/services/scan_solo/ai_agent/model_resolver_spec.rb`, `spec/lib/scansolo_no_enterprise_dependency_spec.rb`
- [ ] T21 — Test mode scaffold: mock LLM responses
      Arquivos: `app/services/scan_solo/test_mode/mock_llm_provider.rb`, `spec/support/scansolo_test_mode.rb`
      Mudança: modo de teste do agente com zero envios reais e suíte completa passando sem credencial de produção.
      Cobre: RF-23, RF-25
      Depende de: T20
      Acceptance criteria: fixture produz resposta simulada e zero envios reais; suíte verde sem `OPENAI_API_KEY`.
      Testes: `spec/services/scan_solo/test_mode/mock_llm_provider_spec.rb`
- [ ] T22 — Controller/routes (CT-02) + Frontend AI Agent Center (UI-03)
      Arquivos: `config/routes.rb`, `app/controllers/api/v1/accounts/scan_solo/ai_agent_configs_controller.rb`, `app/javascript/dashboard/routes/dashboard/scansolo/agent/AgentCenter.vue`
      Mudança: `GET`/`PUT .../draft`/`POST .../publish`; tela expõe todos os campos RF-20 com indicador visível draft-vs-published e bloqueio de publish acidental.
      Cobre: CT-02, UI-03, RF-20, RF-22
      Depende de: T02, T05, T19
      Acceptance criteria: publish exige confirmação explícita na UI.
      Testes: `spec/requests/api/v1/accounts/scan_solo/ai_agent_configs_spec.rb`, `app/javascript/dashboard/routes/dashboard/scansolo/agent/specs/AgentCenter.spec.js`

## Phase 5: Knowledge / RAG

Antes de implementar, leia:
1. `.spec/features/scansolo-chatwoot-platform/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-chatwoot-platform/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-chatwoot-platform/openapi.yaml` — contrato CT-03 implementado em T27

- [ ] T23 — Migration: scan_solo_knowledge_sources + scan_solo_knowledge_chunks
      Arquivos: `db/migrate/XXXXXXXXXXXXXX_create_scan_solo_knowledge_sources.rb`, `db/migrate/XXXXXXXXXXXXXX_create_scan_solo_knowledge_chunks.rb`, `db/migrate/XXXXXXXXXXXXXX_add_embedding_to_scan_solo_knowledge_chunks.rb`
      Mudança: tabelas aditivas usando a coluna `vector` já existente via `pgvector`/`neighbor`.
      Cobre: RF-27, RF-28
      Depende de: T01
      Acceptance criteria: migrations aditivas; `embedding` usa o tipo `vector` existente.
      Testes: `spec/db/scansolo_migrations_spec.rb`
- [ ] T24 — Model: KnowledgeSource/KnowledgeChunk com has_neighbors
      Arquivos: `app/models/scan_solo/knowledge_source.rb`, `app/models/scan_solo/knowledge_chunk.rb`
      Mudança: `has_neighbors :embedding` direto via gem `neighbor`; metadados de origem obrigatórios em cada entrada.
      Cobre: RF-27, RF-28
      Depende de: T23
      Acceptance criteria: uma entrada de cada tipo persiste com metadados e é listável.
      Testes: `spec/models/scan_solo/knowledge_source_spec.rb`
- [ ] T25 — Ingestion service: chunking/embedding, reindex idempotente, reuso de attachment
      Arquivos: `app/services/scan_solo/knowledge/ingestion_service.rb`, `app/services/scan_solo/knowledge/reindex_service.rb`
      Mudança: chunk+embed via stack pgvector/neighbor; reindex idempotente; upload via mecanismo nativo de attachment.
      Cobre: RF-28, RF-31, RF-90
      Depende de: T24
      Acceptance criteria: query de retrieval após ingest retorna pelo menos um chunk; reindex duplo não duplica linhas; upload usa `ActiveStorage`.
      Testes: `spec/services/scan_solo/knowledge/ingestion_service_spec.rb`, `spec/services/scan_solo/knowledge/reindex_service_spec.rb`
- [ ] T26 — Retrieval service: evidência, exclusão de fonte desabilitada, fallback seguro
      Arquivos: `app/services/scan_solo/knowledge/retrieval_service.rb`
      Mudança: cada chunk carrega id de evidência; fonte desabilitada é excluída do retrieval; outage do vector store não falha o turno inteiro.
      Cobre: RF-29, RF-30, RF-34
      Depende de: T24
      Acceptance criteria: outage simulado gera evidência vazia + motivo de falha, sem exceção não tratada.
      Testes: `spec/services/scan_solo/knowledge/retrieval_service_spec.rb`
- [ ] T27 — Controller/routes (CT-03) + Frontend Knowledge screen (UI-05)
      Arquivos: `config/routes.rb`, `app/controllers/api/v1/accounts/scan_solo/knowledge/retrieval_tests_controller.rb`, `app/controllers/api/v1/accounts/scan_solo/knowledge/sources_controller.rb`, `app/javascript/dashboard/routes/dashboard/scansolo/knowledge/KnowledgeCenter.vue`
      Mudança: `POST .../retrieval_tests` (CT-03); `DELETE` de fonte remove conteúdo de retrievals futuros; tela cobre upload/FAQ/enable-disable/reindex/simulador.
      Cobre: CT-03, UI-05, RF-32, RF-33
      Depende de: T02, T05, T25, T26
      Acceptance criteria: cada operação listada é alcançável e funcional na tela.
      Testes: `spec/requests/api/v1/accounts/scan_solo/knowledge/retrieval_tests_spec.rb`, `spec/requests/api/v1/accounts/scan_solo/knowledge/sources_spec.rb`, `app/javascript/dashboard/routes/dashboard/scansolo/knowledge/specs/KnowledgeCenter.spec.js`

## Phase 6: Canonical guarded AI turn flow

Antes de implementar, leia:
1. `.spec/features/scansolo-chatwoot-platform/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-chatwoot-platform/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T28 — Migration: scan_solo_ai_turns
      Arquivos: `db/migrate/XXXXXXXXXXXXXX_create_scan_solo_ai_turns.rb`
      Mudança: tabela aditiva de telemetria por turno, com `message_id` único (dedupe) e `correlation_id` único.
      Cobre: RF-24, RF-35, RF-36
      Depende de: T01
      Acceptance criteria: índice único em `message_id` confirmado no nível de DB.
      Testes: `spec/db/scansolo_migrations_spec.rb`
- [ ] T29 — ScanSolo::ConversationListener + AiTurnJob dedupe
      Arquivos: `app/services/scan_solo/conversation_listener.rb`, `app/jobs/scan_solo/ai_turn_job.rb`
      Mudança: listener assina `message_created`/`conversation_updated` via `Dispatcher` nativo; job só roda após persistência nativa; enfileirar duas vezes produz exatamente uma mensagem e um turno.
      Cobre: RF-35, RF-36, RF-96
      Depende de: T11, T28
      Acceptance criteria: `perform_now` chamado duas vezes para o mesmo `message_id` produz exatamente um `AiTurn` e uma mensagem.
      Testes: `spec/jobs/scan_solo/ai_turn_job_spec.rb`
- [ ] T30 — Turn eligibility guard (checagem de controle humano)
      Arquivos: `app/services/scan_solo/ai_turn/eligibility_guard.rb`
      Mudança: se a conversa está em estado controlado por humano/opt-out, suprime o turno automático de IA.
      Cobre: RF-37
      Depende de: T07, T29
      Acceptance criteria: mensagem inbound em conversa human-owned produz zero mensagens de IA.
      Testes: `spec/services/scan_solo/ai_turn/eligibility_guard_spec.rb`
- [ ] T31 — Context assembler
      Arquivos: `app/services/scan_solo/ai_turn/context_assembler.rb`
      Mudança: monta contexto a partir de histórico canônico, contato, pipeline, proposta e RAG; memória durável é auxiliar subordinada ao histórico canônico.
      Cobre: RF-39, RF-40
      Depende de: T11, T26, T30
      Acceptance criteria: snapshot referencia as cinco fontes ou marcador "não aplicável"; desabilitar memória durável não remove histórico canônico.
      Testes: `spec/services/scan_solo/ai_turn/context_assembler_spec.rb`
- [ ] T32 — Input guardrail + output-claim validation
      Arquivos: `app/services/scan_solo/ai_turn/input_guardrail.rb`, `app/services/scan_solo/ai_turn/output_validator.rb`
      Mudança: guardrail de entrada registrado na evidência do turno; validador de saída bloqueia claim transacional não validado antes do envio.
      Cobre: RF-38, RF-41
      Depende de: T31
      Acceptance criteria: tentativa de afirmar preço sem resultado aprovado de `proposal.generate`/`proposal.send` é bloqueada antes do envio.
      Testes: `spec/services/scan_solo/ai_turn/input_guardrail_spec.rb`, `spec/services/scan_solo/ai_turn/output_validator_spec.rb`
- [ ] T33 — Model invocation via lib/llm + tratamento de falha do provider
      Arquivos: `app/services/scan_solo/ai_turn/model_invoker.rb`
      Mudança: invoca provider resolvido (T20); falha de provider preserva histórico já persistido e não envia mensagem ao cliente.
      Cobre: RF-42
      Depende de: T20, T32
      Acceptance criteria: falha simulada de provider deixa histórico intacto, zero novas mensagens outbound, registra motivo de falha.
      Testes: `spec/services/scan_solo/ai_turn/model_invoker_spec.rb`
- [ ] T34 — Envio de resposta aprovada via caminho nativo + persistência de evidência
      Arquivos: `app/services/scan_solo/ai_turn/response_sender.rb`, `app/services/scan_solo/ai_turn/turn_orchestrator.rb`
      Mudança: envia resposta aprovada só via mensageria nativa; executa ações registradas via T38 antes/no mesmo limite transacional da persistência da resposta final.
      Cobre: RF-43, RF-44, RF-24
      Depende de: T12, T33, T38
      Acceptance criteria: conteúdo persistido da `Message` é idêntico ao entregue; resultado de ação (ex.: transição de stage) visível no registro da oportunidade no máximo quando a mensagem é enfileirada.
      Testes: `spec/services/scan_solo/ai_turn/response_sender_spec.rb`, `spec/services/scan_solo/ai_turn/turn_orchestrator_spec.rb`
- [ ] T35 — Frontend: visualizador de telemetria/evidência por turno (UI-04)
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/agent/TurnEvidenceViewer.vue`
      Mudança: mostra campos de telemetria RF-24 e evidência de guardrail/contexto por turno, consultável por correlation id.
      Cobre: UI-04
      Depende de: T22, T34
      Acceptance criteria: selecionar um turno mostra resultado de guardrail, evidência de conhecimento e evidência de ação.
      Testes: `app/javascript/dashboard/routes/dashboard/scansolo/agent/specs/TurnEvidenceViewer.spec.js`

## Phase 7: Agent actions and tool authorization

Antes de implementar, leia:
1. `.spec/features/scansolo-chatwoot-platform/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-chatwoot-platform/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T36 — Migration: scan_solo_agent_actions + scan_solo_agent_action_executions
      Arquivos: `db/migrate/XXXXXXXXXXXXXX_create_scan_solo_agent_actions.rb`, `db/migrate/XXXXXXXXXXXXXX_create_scan_solo_agent_action_executions.rb`
      Mudança: tabelas aditivas para definições de ação registrada e execuções com `idempotency_key` único.
      Cobre: RF-45, RF-46
      Depende de: T01
      Acceptance criteria: índice único em `idempotency_key` confirmado.
      Testes: `spec/db/scansolo_migrations_spec.rb`
- [ ] T37 — Model: definições de ação registrada + enum de classificação
      Arquivos: `app/models/scan_solo/agent_action.rb`
      Mudança: toda ação tem exatamente uma classificação do conjunto fixo; ação sem classificação não pode ser registrada.
      Cobre: RF-45
      Depende de: T36
      Acceptance criteria: registrar ação sem classificação é rejeitado.
      Testes: `spec/models/scan_solo/agent_action_spec.rb`
- [ ] T38 — Deterministic action executor (CT-04)
      Arquivos: `app/services/scan_solo/actions/executor.rb`
      Mudança: aceita só id de ação registrada + parâmetros validados por schema; parâmetro livre de URL/comando/SQL é rejeitado; execução com mesma idempotency key produz efeito colateral exatamente uma vez.
      Cobre: CT-04, RF-46, RF-47, RNF-01
      Depende de: T08, T09, T37
      Acceptance criteria: log de auditoria vincula execução ao correlation id do turno de origem; parâmetro fora do schema é rejeitado antes de qualquer execução.
      Testes: `spec/services/scan_solo/actions/executor_spec.rb`
- [ ] T39 — Registro do conjunto mínimo de ações comerciais
      Arquivos: `app/services/scan_solo/actions/registry.rb`, `app/services/scan_solo/actions/qualification_field_action.rb`, `app/services/scan_solo/actions/stage_transition_action.rb`, `app/services/scan_solo/actions/private_note_action.rb`, `app/services/scan_solo/actions/proposal_actions.rb`, `app/services/scan_solo/actions/cadence_signal_action.rb`, `app/services/scan_solo/actions/handoff_action.rb`
      Mudança: registra as ações mínimas exigidas (RF-48); ação de atualização de campo de qualificação auto-transiciona estágio quando todos os campos obrigatórios são satisfeitos (RF-16) ou quando a qualificação inicia (RF-15).
      Cobre: RF-48, RF-15, RF-16
      Depende de: T12, T38
      Acceptance criteria: cada ação listada existe, é classificada, validada por schema e exercitada por teste; completar todos os campos obrigatórios auto-transiciona para Qualificado; um campo faltando não altera o stage.
      Testes: `spec/services/scan_solo/actions/registry_spec.rb`, `spec/services/scan_solo/actions/qualification_field_action_spec.rb`
- [ ] T40 — Confirmation-gating para ações requires-confirmation
      Arquivos: `app/services/scan_solo/actions/confirmation_gate.rb`
      Mudança: ação classificada `requires_confirmation` não executa efeito colateral sem autorização confirmadora explícita registrada.
      Cobre: RF-49
      Depende de: T38
      Acceptance criteria: invocação sem confirmação fica pendente e produz zero efeitos colaterais.
      Testes: `spec/services/scan_solo/actions/confirmation_gate_spec.rb`

## Phase 8: Human handoff and control (core)

Antes de implementar, leia:
1. `.spec/features/scansolo-chatwoot-platform/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-chatwoot-platform/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-chatwoot-platform/openapi.yaml` — contrato CT-05 implementado em T42

- [ ] T41 — Handoff service: private note builder + suppressão de resposta de IA
      Arquivos: `app/services/scan_solo/handoff/handoff_service.rb`
      Mudança: ao solicitar handoff, cria exatamente uma nota privada com os nove elementos exigidos; define `ai_control_state` suprimindo respostas automáticas de IA.
      Cobre: RF-50, RF-51, RF-52
      Depende de: T07, T08, T30
      Acceptance criteria: exatamente uma nota privada com todos os nove elementos após handoff; mensagem subsequente produz zero respostas de IA até retorno autorizado.
      Testes: `spec/services/scan_solo/handoff/handoff_service_spec.rb`
- [ ] T42 — Comandos idempotentes de takeover/return-to-AI (CT-05)
      Arquivos: `app/services/scan_solo/handoff/takeover_service.rb`, `app/services/scan_solo/handoff/return_to_ai_service.rb`, `app/controllers/api/v1/accounts/scan_solo/conversations/handoff_controller.rb`, `config/routes.rb`, `app/policies/scan_solo/handoff_policy.rb`
      Mudança: comandos duplicados são idempotentes; return-to-AI exige mesmo nível de permissão que takeover (agente designado ou admin), simétrico, sem novo conceito de autorização.
      Cobre: CT-05, RF-53, RF-54
      Depende de: T02, T09, T41
      Acceptance criteria: tentativa de return-to-AI por usuário não autorizado é rejeitada; comando repetido não gera entrada de auditoria duplicada.
      Testes: `spec/requests/api/v1/accounts/scan_solo/conversations/handoff_controller_spec.rb`
- [ ] T43 — Verificação de histórico nativo (respostas humanas)
      Arquivos: `spec/models/scan_solo/conversation_extension_spec.rb`
      Mudança: confirma que mensagens humanas outbound permanecem na timeline nativa `Message`, sem store paralelo.
      Cobre: RF-55
      Depende de: T41
      Acceptance criteria: resposta humana durante conversa human-active aparece em `conversation.messages`.
      Testes: `spec/models/scan_solo/conversation_extension_spec.rb`
- [ ] T44 — Frontend: indicador de handoff/controle da conversa (UI-06)
      Arquivos: `app/javascript/dashboard/components-next/conversation/HandoffControlBanner.vue`
      Mudança: mostra estado atual de controle de IA e ações de takeover/return; atualiza imediatamente e reflete idempotência do RF-53.
      Cobre: UI-06
      Depende de: T42
      Acceptance criteria: cliques repetidos não produzem flicker de estado duplicado.
      Testes: `app/javascript/dashboard/components-next/conversation/specs/HandoffControlBanner.spec.js`

## Phase 9: Follow-up cadence engine

Antes de implementar, leia:
1. `.spec/features/scansolo-chatwoot-platform/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-chatwoot-platform/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-chatwoot-platform/openapi.yaml` — contrato CT-06 implementado em T56

- [ ] T45 — Migration: cadence_definitions + cadence_enrollments + cadence_attempts
      Arquivos: `db/migrate/XXXXXXXXXXXXXX_create_scan_solo_cadence_definitions.rb`, `db/migrate/XXXXXXXXXXXXXX_create_scan_solo_cadence_enrollments.rb`, `db/migrate/XXXXXXXXXXXXXX_create_scan_solo_cadence_attempts.rb`
      Mudança: tabelas aditivas com índice único `(opportunity_id, cadence_definition_id)`.
      Cobre: RF-57, RF-59, RF-62
      Depende de: T01
      Acceptance criteria: índice único confirmado; migrations puramente aditivas.
      Testes: `spec/db/scansolo_migrations_spec.rb`
- [ ] T46 — Model: CadenceDefinition com schedules seedados
      Arquivos: `app/models/scan_solo/cadence_definition.rb`, `db/seeds/scansolo_cadence_definitions.rb`
      Mudança: seed das 3 definições iniciais (Novo Lead +2h/+24h/+48h/+96h; Em Contato 5x/24h; Em Qualificação 7x/24h).
      Cobre: RF-57
      Depende de: T45
      Acceptance criteria: inscrever fixture em cada cadência agenda exatamente as tentativas/offsets especificados.
      Testes: `spec/models/scan_solo/cadence_definition_spec.rb`
- [ ] T47 — Native template-send wrapper
      Arquivos: `app/services/scan_solo/messaging/native_template_sender.rb`
      Mudança: reusa caminho nativo `template_params` de criação de mensagem; suporta templates fake; nunca marca como enviado antes da aceitação nativa do transporte.
      Cobre: RF-70, RF-71, RF-72
      Depende de: T02
      Acceptance criteria: suíte completa de cadência/proposta passa com identificadores fake e zero chamadas reais ao Meta; rejeição simulada de transporte deixa evidência como não-enviado.
      Testes: `spec/services/scan_solo/messaging/native_template_sender_spec.rb`
- [ ] T48 — Enrollment service: inscrição idempotente
      Arquivos: `app/services/scan_solo/cadence/enrollment_service.rb`
      Mudança: inscrever duas vezes com mesmos inputs resulta em exatamente uma inscrição ativa.
      Cobre: RF-59
      Depende de: T45, T46
      Acceptance criteria: chamar inscrição duas vezes resulta em exatamente um registro ativo.
      Testes: `spec/services/scan_solo/cadence/enrollment_service_spec.rb`
- [ ] T49 — Due-attempt processor: sidekiq-cron + janela de envio + no-duplicate-on-retry
      Arquivos: `app/jobs/scan_solo/cadence_due_attempt_job.rb`, `config/schedule.yml`, `app/services/scan_solo/cadence/sending_window.rb`
      Mudança: registra job `sidekiq-cron` a cada 5min; envia só entre 09:00–20:00 America/Sao_Paulo; job repetido para step já enviado produz zero envios adicionais.
      Cobre: RF-58, RF-60, RF-61
      Depende de: T47, T48
      Acceptance criteria: tentativa calculada para 21:00 não é enviada antes das 09:00 seguintes; job repetido não duplica envio.
      Testes: `spec/jobs/scan_solo/cadence_due_attempt_job_spec.rb`
- [ ] T50 — Persistência de evidência de tentativa + exposição de próxima tentativa/step atual
      Arquivos: `app/services/scan_solo/cadence/attempt_evidence_recorder.rb`, `app/serializers/scan_solo/cadence_enrollment_serializer.rb`
      Mudança: evidência imutável por tentativa, nunca atualizada após resultado terminal; expõe step atual e próxima tentativa.
      Cobre: RF-62, RF-63
      Depende de: T49
      Acceptance criteria: cada tentativa tem exatamente um registro de evidência; `next_attempt_at` serializado corresponde ao valor persistido.
      Testes: `spec/services/scan_solo/cadence/attempt_evidence_recorder_spec.rb`
- [ ] T51 — Pause/resume/cancel + inscrição manual autorizada + aceleração de test-mode
      Arquivos: `app/services/scan_solo/cadence/lifecycle_service.rb`, `app/policies/scan_solo/cadence_enrollment_policy.rb`
      Mudança: pausar impede próxima tentativa; resume rearma no offset correto; cancel para permanentemente; inscrição manual só com autorização explícita.
      Cobre: RF-64, RF-68
      Depende de: T48, T09
      Acceptance criteria: requisição de inscrição manual não autorizada é rejeitada (4xx); test-mode avança por todas as tentativas sem espera real.
      Testes: `spec/services/scan_solo/cadence/lifecycle_service_spec.rb`
- [ ] T52 — Serviço de detecção de resposta completa/parcial do cliente
      Arquivos: `app/services/scan_solo/cadence/reply_completeness_detector.rb`
      Mudança: detecção determinística por completude de campo (sem NLP); resposta completa para/recalcula toda a agenda pendente; resposta parcial cancela só o próximo envio pendente.
      Cobre: RF-65
      Depende de: T51
      Acceptance criteria: fixture completando todos os campos obrigatórios para/recalcula a agenda inteira; fixture com campo faltando cancela só o envio imediato.
      Testes: `spec/services/scan_solo/cadence/reply_completeness_detector_spec.rb`
- [ ] T53 — Serviço unificado de stop/recalculate (mudança de stage/won/lost/opt-out/pausa manual/substituição + takeover humano)
      Arquivos: `app/services/scan_solo/cadence/stop_recalculate_policy.rb`
      Mudança: serviço único acionado pelos seis gatilhos de RF-66 e pelo takeover humano de RF-56, reutilizando o hook de transição de stage (T12) e o evento de takeover (T41).
      Cobre: RF-56, RF-66
      Depende de: T12, T41, T51, T52
      Acceptance criteria: cada um dos seis gatilhos tem asserção passando de que a agenda pendente é parada/recalculada; takeover pausa/cancela step agendado-mas-não-enviado no mesmo ciclo de processamento, sem alterar step já enviado.
      Testes: `spec/services/scan_solo/cadence/stop_recalculate_policy_spec.rb`
- [ ] T54 — Safe-skip para template indisponível/automação desabilitada
      Arquivos: `app/services/scan_solo/cadence/template_availability_guard.rb`
      Mudança: template não disponível/aprovado, ou automação desabilitada, não envia a tentativa e registra resultado de skip/falha seguro.
      Cobre: RF-67
      Depende de: T47, T49
      Acceptance criteria: fixture com template ausente/não aprovado produz evidência de skip/falha registrada e zero tentativas de envio.
      Testes: `spec/services/scan_solo/cadence/template_availability_guard_spec.rb`
- [ ] T55 — Verificação de no-LLM-timing
      Arquivos: `spec/services/scan_solo/cadence/no_llm_timing_spec.rb`
      Mudança: verificação estática de que nenhum cálculo de agendamento de cadência depende de chamada LLM.
      Cobre: RF-69
      Depende de: T49
      Acceptance criteria: busca no repositório em `app/services/scan_solo/cadence/**/*.rb` não encontra referência a `Llm::`/`ScanSolo::AiAgent`.
      Testes: `spec/services/scan_solo/cadence/no_llm_timing_spec.rb`
- [ ] T56 — Controller/routes (CT-06) + Frontend Follow-ups screen (UI-07)
      Arquivos: `config/routes.rb`, `app/controllers/api/v1/accounts/scan_solo/cadence_enrollments_controller.rb`, `app/javascript/dashboard/routes/dashboard/scansolo/followups/FollowUps.vue`
      Mudança: `POST`/`.../pause`/`.../resume`/`.../cancel` implementando CT-06; tela mostra inscrições ativas, step atual, próxima tentativa, controles pause/resume/cancel.
      Cobre: CT-06, UI-07
      Depende de: T02, T05, T50, T51
      Acceptance criteria: pausar pela tela reflete no estado persistido no mesmo ciclo requisição/resposta.
      Testes: `spec/requests/api/v1/accounts/scan_solo/cadence_enrollments_spec.rb`, `app/javascript/dashboard/routes/dashboard/scansolo/followups/specs/FollowUps.spec.js`

## Phase 10: Proposal automation

Antes de implementar, leia:
1. `.spec/features/scansolo-chatwoot-platform/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-chatwoot-platform/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-chatwoot-platform/openapi.yaml` — contrato CT-07 implementado em T65

- [ ] T57 — Migration: scan_solo_proposals + scan_solo_proposal_versions
      Arquivos: `db/migrate/XXXXXXXXXXXXXX_create_scan_solo_proposals.rb`, `db/migrate/XXXXXXXXXXXXXX_create_scan_solo_proposal_versions.rb`
      Mudança: tabelas aditivas para proposta e suas versões.
      Cobre: RF-77
      Depende de: T01
      Acceptance criteria: migrations puramente aditivas.
      Testes: `spec/db/scansolo_migrations_spec.rb`
- [ ] T58 — Model: Proposal/ProposalVersion com integridade de versão atual
      Arquivos: `app/models/scan_solo/proposal.rb`, `app/models/scan_solo/proposal_version.rb`
      Mudança: apenas uma versão `is_current: true` por oportunidade, via índice único parcial + callback.
      Cobre: RF-77
      Depende de: T57
      Acceptance criteria: gerar nova versão marca a anterior como não-atual.
      Testes: `spec/models/scan_solo/proposal_version_spec.rb`
- [ ] T59 — Serviço proposal.generate
      Arquivos: `app/services/scan_solo/proposal/generate_service.rb`
      Mudança: rejeita geração se campos obrigatórios não estão completos; solicita geração só via Make registrado (ou mock); nunca escreve valor/preço a partir da saída bruta do modelo.
      Cobre: RF-73, RF-74, RF-75, RF-76
      Depende de: T58, T67
      Acceptance criteria: fixture com campo faltando é rejeitada sem criar proposta; `proposal.generate` isolado não envia nada; saída bruta do modelo nunca é escrita em price/discount/total.
      Testes: `spec/services/scan_solo/proposal/generate_service_spec.rb`
- [ ] T60 — Serviço proposal.approve
      Arquivos: `app/services/scan_solo/proposal/approve_service.rb`
      Mudança: quando aprovação é exigida, bloqueia `proposal.send` até aprovação explícita registrada.
      Cobre: RF-78
      Depende de: T58
      Acceptance criteria: com aprovação exigida, envio sem aprovação registrada é rejeitado; sem exigência, envio prossegue direto.
      Testes: `spec/services/scan_solo/proposal/approve_service_spec.rb`
- [ ] T61 — Serviço proposal.send + tratamento idempotente de callback
      Arquivos: `app/services/scan_solo/proposal/send_service.rb`, `app/services/scan_solo/proposal/callback_handler.rb`
      Mudança: `proposal.send` exige resultado prévio de `proposal.generate` bem-sucedido (e aprovação quando exigida) para a mesma versão; envio contra versão obsoleta é rejeitado; nunca reporta sucesso antes de resultado validado.
      Cobre: RF-73, RF-77, RF-79, RF-80
      Depende de: T47, T58, T60, T68
      Acceptance criteria: falha simulada de envio deixa status como não-enviado; entregar o mesmo callback mock duas vezes resulta em exatamente uma mudança de estado persistida.
      Testes: `spec/services/scan_solo/proposal/send_service_spec.rb`
- [ ] T62 — Política de retry seguro para falhas de integração de proposta
      Arquivos: `app/services/scan_solo/proposal/retry_policy.rb`
      Mudança: retry só para falhas seguramente retentáveis; nunca retry automático de operação em estado de efeito colateral inseguro.
      Cobre: RF-81
      Depende de: T61
      Acceptance criteria: falha retentável é retentada sem duplicar proposta/envio; falha insegura fica para revisão manual.
      Testes: `spec/services/scan_solo/proposal/retry_policy_spec.rb`
- [ ] T63 — Transição de stage + inscrição de cadência no sucesso
      Arquivos: `app/services/scan_solo/proposal/success_handler.rb`
      Mudança: envio validado como bem-sucedido transiciona a oportunidade para `proposta_enviada` e inscreve na cadência pós-proposta configurada.
      Cobre: RF-17, RF-82
      Depende de: T12, T48, T61
      Acceptance criteria: fixture de envio bem-sucedido mock produz transição de stage e nova inscrição de cadência ativa.
      Testes: `spec/services/scan_solo/proposal/success_handler_spec.rb`
- [ ] T64 — Mock proposal provider
      Arquivos: `app/services/scan_solo/proposal/mock_provider.rb`
      Mudança: provider mock utilizável sem qualquer credencial real de produção.
      Cobre: RF-83
      Depende de: T61
      Acceptance criteria: suíte completa de proposta (T59–T63) passa só com este provider configurado.
      Testes: `spec/services/scan_solo/proposal/mock_provider_spec.rb`
- [ ] T65 — Controller/routes (CT-07) + Frontend Propostas screen (UI-08)
      Arquivos: `config/routes.rb`, `app/controllers/api/v1/accounts/scan_solo/proposals_controller.rb`, `app/javascript/dashboard/routes/dashboard/scansolo/proposals/Proposals.vue`
      Mudança: `POST .../generate`/`.../approve`/`.../send` implementando CT-07; tela mostra versões, status current/non-current, estado de aprovação, com envio desabilitado quando não aprovado e aprovação exigida.
      Cobre: CT-07, UI-08
      Depende de: T02, T05, T59, T60, T61
      Acceptance criteria: ação de envio fica desabilitada na UI quando a versão atual não está aprovada e aprovação é exigida.
      Testes: `spec/requests/api/v1/accounts/scan_solo/proposals_spec.rb`, `app/javascript/dashboard/routes/dashboard/scansolo/proposals/specs/Proposals.spec.js`

## Phase 11: Make integration platform

Antes de implementar, leia:
1. `.spec/features/scansolo-chatwoot-platform/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-chatwoot-platform/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-chatwoot-platform/asyncapi.yaml` — contratos CT-08/CT-09 implementados em T67/T68

- [ ] T66 — Migration: scan_solo_make_requests + scan_solo_make_callbacks
      Arquivos: `db/migrate/XXXXXXXXXXXXXX_create_scan_solo_make_requests.rb`, `db/migrate/XXXXXXXXXXXXXX_create_scan_solo_make_callbacks.rb`
      Mudança: tabelas aditivas; `correlation_id` de `scan_solo_make_callbacks` com índice único permanente, sem TTL/expiração.
      Cobre: RNF-06
      Depende de: T01
      Acceptance criteria: índice único de `correlation_id` confirmado sem mecanismo de expiração associado.
      Testes: `spec/db/scansolo_migrations_spec.rb`
- [ ] T67 — Outbound Make request service
      Arquivos: `app/services/scan_solo/make/outbound_request_service.rb`, `config/credentials.yml.enc`
      Mudança: configuração do Make registrada só server-side, segredos criptografados em repouso; sem chamada Make no caminho padrão de resposta a menos que ação registrada exija; correlation id + idempotency key em toda requisição outbound.
      Cobre: CT-08, RF-84, RF-85
      Depende de: T02
      Acceptance criteria: nenhuma chamada HTTP ao Make ocorre durante turno padrão sem ação Make-backed; credenciais nunca aparecem em payload client-facing.
      Testes: `spec/services/scan_solo/make/outbound_request_service_spec.rb`
- [ ] T68 — Inbound Make callback controller (CT-09)
      Arquivos: `config/routes.rb`, `app/controllers/webhooks/scan_solo/make_controller.rb`, `app/services/scan_solo/make/callback_verifier.rb`
      Mudança: valida assinatura/autenticidade/replay antes de qualquer mudança de estado; valida payload contra schema registrado; rejeita callback referenciando correlation id não emitido para aquela ação.
      Cobre: CT-09, RF-85, RF-86, RF-87, RNF-06
      Depende de: T02, T09, T66
      Acceptance criteria: callback com assinatura inválida/repetida é rejeitado sem mudança de estado; callback malformado é rejeitado e registrado como erro sem mutar estado de proposta/pipeline.
      Testes: `spec/requests/webhooks/scan_solo/make_controller_spec.rb`
- [ ] T69 — Rack::Attack throttle escopado ao endpoint de callback do Make
      Arquivos: `config/initializers/rack_attack.rb`
      Mudança: regra de throttle aplicada só ao endpoint de callback inbound do Make, dentro do range existente (5–3000/min).
      Cobre: RNF-05
      Depende de: T68
      Acceptance criteria: throttle presente e escopado a `webhooks/scan_solo/make`; nenhum throttle em endpoints de turno de IA ou inscrição manual de cadência.
      Testes: `spec/requests/webhooks/scan_solo/make_controller_spec.rb`
- [ ] T70 — Model/query de visibilidade de dead-letter/erro
      Arquivos: `app/models/scan_solo/make_request.rb`, `app/services/scan_solo/make/dead_letter_query.rb`
      Mudança: fornece visibilidade de retry/dead-letter/erro para requisições outbound falhadas, alimentando a tela de Execuções e auditoria.
      Cobre: RF-86
      Depende de: T67
      Acceptance criteria: requisição outbound repetidamente falhada é visível via esta query.
      Testes: `spec/services/scan_solo/make/dead_letter_query_spec.rb`

## Phase 12: Security & privacy hardening (cross-cutting verification)

Antes de implementar, leia:
1. `.spec/features/scansolo-chatwoot-platform/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-chatwoot-platform/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T71 — Redação de segredos: logs + payloads de prompt do LLM
      Arquivos: `config/initializers/scansolo_log_redaction.rb`, `app/services/scan_solo/ai_turn/prompt_redactor.rb`
      Mudança: segredos de integração ScanSolo só server-side, nunca em resposta client-facing, prompt de modelo ou logs.
      Cobre: RF-88, RNF-07
      Depende de: T31, T67
      Acceptance criteria: valor com formato de segredo (API key) ausente/redigido em linha de log renderizada e em payload de prompt renderizado.
      Testes: `spec/services/scan_solo/ai_turn/prompt_redactor_spec.rb`
- [ ] T72 — Auditoria de cobertura fail-closed do Pundit
      Arquivos: `spec/policies/scan_solo/coverage_audit_spec.rb`
      Mudança: spec de auditoria repositório-wide garantindo que todo controller `ScanSolo::` tem policy Pundit correspondente herdando de `ScanSolo::ApplicationPolicy`.
      Cobre: RF-89
      Depende de: T13, T22, T27, T42, T56, T65, T68
      Acceptance criteria: todo controller sob `api/v1/accounts/scan_solo/` e `webhooks/scan_solo/` tem policy correspondente.
      Testes: `spec/policies/scan_solo/coverage_audit_spec.rb`
- [ ] T73 — Auditoria de reuso do caminho de upload de attachment
      Arquivos: `spec/services/scan_solo/knowledge/upload_path_audit_spec.rb`
      Mudança: confirma que o upload de documento do Knowledge é o único caminho novo de escrita de arquivo e delega ao mecanismo nativo de attachment.
      Cobre: RF-90
      Depende de: T25
      Acceptance criteria: busca no repositório não encontra `File.write`/`IO.write`/cliente S3 bruto fora de `ActiveStorage` sob `app/**/scan_solo/**`.
      Testes: `spec/services/scan_solo/knowledge/upload_path_audit_spec.rb`

## Phase 13: Execuções e auditoria

Antes de implementar, leia:
1. `.spec/features/scansolo-chatwoot-platform/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-chatwoot-platform/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T74 — Controller/routes: listagem de auditoria/execução
      Arquivos: `config/routes.rb`, `app/controllers/api/v1/accounts/scan_solo/executions_controller.rb`
      Mudança: expõe evidência de cadência, visibilidade de erro/dead-letter do Make e registros de auditoria de ação em um endpoint consultável.
      Cobre: UI-09
      Depende de: T02, T50, T70, T38
      Acceptance criteria: callback Make falhado simulado aparece na resposta.
      Testes: `spec/requests/api/v1/accounts/scan_solo/executions_spec.rb`
- [ ] T75 — Frontend: tela Execuções e auditoria (UI-09)
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/executions/Executions.vue`
      Mudança: renderiza evidência de cadência, view de erro/dead-letter do Make e registros de auditoria de ação.
      Cobre: UI-09
      Depende de: T05, T74
      Acceptance criteria: fixture de callback falhado renderiza na view de erro.
      Testes: `app/javascript/dashboard/routes/dashboard/scansolo/executions/specs/Executions.spec.js`

## Phase 14: Test mode consolidation

Antes de implementar, leia:
1. `.spec/features/scansolo-chatwoot-platform/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-chatwoot-platform/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T76 — Suíte de integração completa do modo de teste isolado + enforcement webmock
      Arquivos: `spec/support/scansolo_webmock_enforcement.rb`, `spec/integration/scan_solo/full_test_mode_spec.rb`
      Mudança: cobre conversas/mensagens fake, respostas mock de LLM, retrieval RAG, evidência de ação/ferramenta, transições de pipeline, takeover/return humano, agendamento de cadência acelerado, templates fake, request/callback mock do Make, artefato/valor mock de proposta, comportamento de retry/evento duplicado.
      Cobre: RF-91, RNF-03
      Depende de: T21, T29, T34, T42, T51, T64, T68
      Acceptance criteria: suíte completa roda sem credencial de produção presente e zero requisições outbound reais.
      Testes: `bundle exec rspec spec/integration/scan_solo/`, `pnpm test -- scansolo`
- [ ] T77 — Matriz de rastreabilidade de resultado de aceitação da §20
      Arquivos: `docs/architecture/SCANSOLO_ACCEPTANCE_TRACEABILITY.md`
      Mudança: mapeia cada um dos itens 1–19 da §20 da descrição para seu(s) teste(s) automatizado(s) correspondente(s).
      Cobre: RF-92
      Depende de: T76
      Acceptance criteria: todo arquivo de spec referenciado na matriz existe e passa.
      Testes: `spec/integration/scan_solo/acceptance_traceability_spec.rb`

## Phase 15: Deployment documentation

Antes de implementar, leia:
1. `.spec/features/scansolo-chatwoot-platform/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-chatwoot-platform/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T78 — Documentação de deployment Docker Compose + rollback
      Arquivos: `docs/architecture/SCANSOLO_DEPLOYMENT.md`, `docker-compose.scansolo.yaml`
      Mudança: documenta web, Sidekiq, PostgreSQL, Redis, storage S3-compatible, reverse proxy/TLS, health checks, volumes, migrations, restart policy, backup/restore, env vars, log rotation, rollback. Nenhum deploy real, cutover de DNS ou ativação de provider ocorre nesta tarefa.
      Cobre: RF-93, RF-94
      Depende de: T02
      Acceptance criteria: `docker compose -f docker-compose.yaml -f docker-compose.scansolo.yaml config` valida sem erro (lint apenas, sem `up` real).
      Testes: `spec/lib/scansolo_deployment_doc_spec.rb`

## Phase 16: Upstream maintainability

Antes de implementar, leia:
1. `.spec/features/scansolo-chatwoot-platform/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-chatwoot-platform/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T79 — Verificação de migration aditiva/namespace isolado
      Arquivos: `spec/db/scansolo_migrations_spec.rb`
      Mudança: assertion final consolidada de que toda migration criada por este plano é `create_table`/`add_column` aditivo puro, sem `remove_column`/`change_column` em tabela pré-existente.
      Cobre: RF-95, RNF-04
      Depende de: T06, T10, T18, T23, T28, T36, T45, T57, T66
      Acceptance criteria: parse de todas as migrations sob `db/migrate/` criadas por este plano confirma apenas statements aditivos.
      Testes: `spec/db/scansolo_migrations_spec.rb`
- [ ] T80 — Documentação de customizações de alto risco upstream
      Arquivos: `docs/architecture/SCANSOLO_UPSTREAM_RISK.md`
      Mudança: documenta toda customização de alto risco de conflito de merge contra `chatwoot/chatwoot` upstream, com racional; confirma que todo evento de domínio ScanSolo passa pelo `Dispatcher`/`AsyncDispatcher` existente.
      Cobre: RF-96, RF-97
      Depende de: T02, T29
      Acceptance criteria: documento lista pelo menos `config/routes.rb` e a adição de flag em `Account`; busca no repositório confirma ausência de novo mecanismo de pub/sub sob `app/**/scan_solo/**`.
      Testes: `spec/lib/scansolo_dispatcher_reuse_spec.rb`

## Phase 17: Lexus migration design

Antes de implementar, leia:
1. `.spec/features/scansolo-chatwoot-platform/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-chatwoot-platform/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T81 — Documento de design de migração/cutover
      Arquivos: `docs/migration/SCANSOLO_LEXUS_CUTOVER_DESIGN.md`
      Mudança: documenta design de migração/cutover para identidade de contato, estado de pipeline ativo, campos de qualificação, estado/referência de proposta, estado de cadência, configuração de agente, fontes de conhecimento, mapeamentos de template aprovados, estado de ownership/handoff humano — com decisão explícita (migrar/re-derivar/descartar) por categoria. Nenhuma escrita real contra Lexus produção ocorre nesta tarefa.
      Cobre: RF-98, RF-99
      Depende de: T11, T19, T24, T46, T58
      Acceptance criteria: documento contém linha de decisão explícita para cada categoria listada.
      Testes: `spec/lib/scansolo_migration_design_doc_spec.rb`

## Phase 18: Deferred production activation: human-approval gates (RF-100)

Antes de implementar, leia:
1. `.spec/features/scansolo-chatwoot-platform/SPEC.md` — requisitos RIGID que esta fase cobre (RF-100, §19)
2. `.spec/features/scansolo-chatwoot-platform/PLAN.md` — decomposição completa, dependências e riscos

Cada item abaixo é um checkpoint não-código e não-autônomo. Nenhuma tarefa anterior ou posterior deste plano pode realizar a ação que um gate cobre. Ralph (ou qualquer agente) nunca deve marcar estas caixas — elas só são marcadas por um humano, fora da execução automatizada, após revisar a suíte de testes passando das fases anteriores.

- [ ] T82 — GATE: Ativação de provider (credencial de produção real do OpenAI)
      Arquivos: nenhum (aprovação registrada, ex.: comentário na issue/PR de acompanhamento)
      Mudança: bloqueia configurar segredo de produção do OpenAI/provider de modelo em qualquer ambiente até aprovação humana explícita.
      Cobre: RF-100
      Depende de: T21, T76
      Acceptance criteria: aprovação humana registrada existe antes de qualquer pipeline de deploy configurar a credencial; nenhum agente marca esta caixa autonomamente.
      Testes: n/a — não há código a testar; verificação é a aprovação humana registrada, não um comando automatizado.
- [ ] T83 — GATE: Deploy de produção na VPS
      Arquivos: nenhum
      Mudança: bloqueia qualquer deploy de produção usando a documentação Docker Compose (T78) até aprovação humana explícita.
      Cobre: RF-94, RF-100
      Depende de: T78
      Acceptance criteria: aprovação humana registrada existe antes de qualquer `docker compose up` contra host de produção.
      Testes: n/a — verificação é a aprovação humana registrada; `spec/lib/scansolo_deployment_doc_spec.rb` (T78) só valida config, nunca executa `up` real.
- [ ] T84 — GATE: Execução de migrations de banco em produção
      Arquivos: nenhum
      Mudança: bloqueia rodar `bin/rails db:migrate` contra qualquer banco de produção até aprovação humana explícita.
      Cobre: RF-100
      Depende de: T79, T83
      Acceptance criteria: aprovação humana registrada existe antes de qualquer execução de migration em produção.
      Testes: n/a — verificação é a aprovação humana registrada; T79 só valida conteúdo das migrations, nunca as executa em produção.
- [ ] T85 — GATE: Cutover de DNS sob scansolo.com.br
      Arquivos: nenhum
      Mudança: bloqueia trocar o DNS final sob `scansolo.com.br` até aprovação humana explícita.
      Cobre: RF-04, RF-100
      Depende de: T83
      Acceptance criteria: aprovação humana registrada existe antes de qualquer mudança de DNS.
      Testes: n/a — verificação é a aprovação humana registrada; T04 só confirma ausência de hostname hardcoded em lógica de aplicação.
- [ ] T86 — GATE: Conexão real do número WhatsApp / webhook Meta de produção
      Arquivos: nenhum
      Mudança: bloqueia conectar o número real de WhatsApp do ScanSolo e alterar o webhook Meta de produção atual até aprovação humana explícita.
      Cobre: RF-100
      Depende de: T47, T76, T85
      Acceptance criteria: aprovação humana registrada existe antes de qualquer conexão real com número/webhook de produção.
      Testes: n/a — verificação é a aprovação humana registrada; T47/T76 confirmam suíte completa passando com templates fake e zero chamadas reais ao Meta antes deste gate.
- [ ] T87 — GATE: Cenários/callbacks reais de produção do Make
      Arquivos: nenhum
      Mudança: bloqueia habilitar cenários/callbacks de produção do Make (apontar T67/T68 para endpoints/segredos reais) até aprovação humana explícita.
      Cobre: RF-100
      Depende de: T67, T68, T76
      Acceptance criteria: aprovação humana registrada existe antes de qualquer configuração de Make de produção.
      Testes: n/a — verificação é a aprovação humana registrada; T64/T76 confirmam suíte completa de proposta/Make passando no provider mock antes deste gate.
- [ ] T88 — GATE: Credenciais reais de produção da API de proposta
      Arquivos: nenhum
      Mudança: bloqueia configurar credenciais reais de produção da API de proposta até aprovação humana explícita.
      Cobre: RF-100
      Depende de: T64, T76, T87
      Acceptance criteria: aprovação humana registrada existe antes de qualquer configuração de credencial real de proposta.
      Testes: n/a — verificação é a aprovação humana registrada; T64/T76 confirmam suíte completa passando no provider mock antes deste gate.
- [ ] T89 — GATE: Cutover de produção do Lexus (migrar dados + desabilitar Lexus)
      Arquivos: nenhum
      Mudança: bloqueia migrar dados de produção do Lexus e desabilitar o ScanSolo no Lexus até aprovação humana explícita.
      Cobre: RF-99, RF-100
      Depende de: T81, T84, T86, T87, T88
      Acceptance criteria: aprovação humana registrada existe antes de qualquer escrita real contra o Lexus de produção.
      Testes: n/a — verificação é a aprovação humana registrada; T81 é o único artefato produzido antes deste gate.
- [ ] T90 — GATE: Provisionamento de segredos de produção
      Arquivos: nenhum
      Mudança: bloqueia provisionar qualquer segredo de produção referenciado por T82/T86/T87/T88 (chave OpenAI, token Meta de produção, credenciais Make de produção, credenciais de API de proposta de produção) no cofre de segredos do deployment até aprovação humana explícita.
      Cobre: RF-88, RF-100
      Depende de: T67, T71, T83
      Acceptance criteria: aprovação humana registrada existe antes de qualquer segredo de produção entrar em variável de ambiente, cofre de credenciais ou chave de produção de `config/credentials.yml.enc`.
      Testes: n/a — verificação é a aprovação humana registrada; T71 confirma ausência de vazamento de valor com formato de segredo em logs/prompts, independentemente de quais segredos forem eventualmente provisionados.
