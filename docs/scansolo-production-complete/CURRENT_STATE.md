# ScanSolo Production Complete — Estado Atual

Gerado em 2026-09-23 a partir do commit 4af19b0bb (branch feat/scansolo-production-complete). Documento factual — não implementa nada.

Documentos relacionados: [ARCHITECTURE_MAP](ARCHITECTURE_MAP.md) · [GAP_ANALYSIS](GAP_ANALYSIS.md) · [DECISIONS_REQUIRED](DECISIONS_REQUIRED.md) · [RISK_REGISTER](RISK_REGISTER.md)

Convenções: todas as referências são `arquivo:linha` relativas à raiz do repo. "Reportado pelo usuário" = fato de produção que não dá para verificar pelo repositório. `FE` = `app/javascript/dashboard/routes/dashboard/scansolo`, `ST` = `app/javascript/dashboard/store/scansolo`.

---

## 0. Resumo executivo

**O que existe:** uma camada ScanSolo completa em estrutura sobre o Chatwoot OSS:
- 18 tabelas `scan_solo_*` e 21 migrations, de `db/migrate/20260917231850_*` a `20260918080001_*`.
- Agente de IA com draft/publish.
- RAG com pgvector.
- Cadências via sidekiq-cron.
- Pipeline de 8 estágios, handoff, propostas e callback Make.
- 6 módulos no dashboard.
- 73 specs Ruby, 2 arquivos de suporte e 11 specs de frontend.

WhatsApp usa exclusivamente o canal nativo Cloud API. Não há Evolution nem cliente HTTP paralelo.

**O que não funciona ponta a ponta em produção hoje** (todos verificados no código):

| # | Bloqueio | Evidência |
|---|---|---|
| 1 | O prompt enviado ao LLM contém **só o histórico**. O RAG é recuperado e gravado no turno, mas nunca chega ao modelo. | `app/services/scan_solo/ai_turn/turn_orchestrator.rb:154-157` |
| 2 | **Nenhum código cria `PipelineOpportunity`.** Pipeline, cadências, propostas e transição automática nunca começam para um lead real. | grep sem `create/new` fora de specs; rotas só `index/show/update`, `config/routes.rb:463` |
| 3 | Propostas usam `MockProvider` por padrão (R$ 1500,00 e URL falsa). `OutboundRequestService` (Make) não tem chamador. O callback Make não atualiza `ProposalVersion`. | `generate_service.rb:12`, `send_service.rb:10`, `mock_provider.rb:14-27`, `make_controller.rb:39-49` |
| 4 | A camada de ações da IA (`Actions::Registry`) é inalcançável. A IA não faz handoff, não captura qualificação e não faz opt-out. | `conversation_listener.rb:17` (sem `actions`), `turn_orchestrator.rb:18` |
| 5 | Resposta humana nativa não pausa a IA, e a elegibilidade não é rechecada antes do envio. IA e humano podem responder juntos. | `conversation_listener.rb:12`, `turn_orchestrator.rb:30-41` |
| 6 | Turno pode ficar `pending` para sempre. Exceções fora de `PROVIDER_ERRORS` não são tratadas e o retry do Sidekiq bate no índice único. | `model_invoker.rb:16`, `turn_orchestrator.rb:47-56` |
| 7 | Agent Center (e todas as telas ScanSolo) sem scroll vertical. | `Dashboard.vue:142-143` (`overflow-hidden`), `AgentCenter.vue:115` |
| 8 | 10 chaves i18n cruas no Agent Center: `field.toUpperCase()` sobre camelCase gera `MODELPROVIDER`, mas o JSON tem `MODEL_PROVIDER`. | `AgentCenter.vue:157,169,181`, `en/scansolo.json:76` |
| 9 | `docker-compose.production.yaml` tem `POSTGRES_PASSWORD=` vazio, e a documentação empilha o compose de **dev** no comando de produção. | `docker-compose.production.yaml:51`, `SCANSOLO_DEPLOYMENT.md:40-41` |
| 10 | Seeds das `CadenceDefinition` não são carregados por `db/seeds.rb` nem pelo runbook. Em produção a tabela tende a estar vazia, e o enroll pós-proposta é pulado em silêncio. | `db/seeds/scansolo_cadence_definitions.rb` carregado só em `spec/models/scan_solo/cadence_definition_spec.rb:7`; `success_handler.rb:36-37` |
| 11 | Coexistência com Captain não tratada. Em inbox com Captain ativo, os dois podem responder. | `enterprise/app/services/enterprise/message_templates/hook_execution_service.rb:11-14`; nenhum `captain_active` em `app/services/scan_solo` |

---

## 1. Fatos de produção (reportado pelo usuário, não verificável no repo)

- VPS provisionada. Docker, PostgreSQL+pgvector, Redis, Rails, Sidekiq e Nginx/TLS em execução (reportado pelo usuário).
  - O repo traz Caddy como proxy opcional (profile `reverse-proxy`, `docker-compose.scansolo.yaml:90-111`). A VPS usa **Nginx**, que não está versionado.
- Conta ScanSolo com id 1 e `scansolo_enabled` ligado (reportado pelo usuário). O repo não tem UI nem task para ligar a flag (ver §2.12).
- Os 6 módulos aparecem no menu (reportado pelo usuário). Isso é consistente com `Sidebar.vue:58-59,601-610`.
- `CAPTAIN_OPEN_AI_API_KEY` salva em `InstallationConfig` de produção e validada (reportado pelo usuário).
  - Observação de código: `Llm::Config.initialize!` memoriza a inicialização por processo (`lib/llm/config.rb:11-16`). Se a chave foi salva depois do boot, Rails e Sidekiq precisam reiniciar para usá-la.
- Modelo inicial `gpt-4.1-mini` (reportado pelo usuário). É o default de `scansolo_agent_response` (`config/llm.yml:205-215`).
- Correção manual de `POSTGRES_PASSWORD` aplicada na VPS (reportado pelo usuário). Existe drift entre a VPS e o Git, porque `docker-compose.production.yaml:51` continua vazio.
- Sintomas observados (reportado pelo usuário):
  - Agent Center sem scroll vertical.
  - Chaves cruas como `SCANSOLO.AGENT_CENTER.FIELDS.MODELPROVIDER`.
  - Ambos confirmados no código (§2.13).

---

## 2. Estado por área

### 2.1 Configuração do agente de IA
- **Modelo** `ScanSolo::AiAgentConfig` (`app/models/scan_solo/ai_agent_config.rb:44-68`):
  - `status` draft/published (`:57`).
  - Um draft por conta, garantido por índice parcial único (`db/migrate/20260918020000_create_scan_solo_ai_agent_configs.rb:45-50`).
  - Versões publicadas são snapshots imutáveis, apontados por `published_version_id` (`:55,65-67`).
- **Publicação:** `PublishService` cria o snapshot e troca o ponteiro numa transação (`app/services/scan_solo/ai_agent/publish_service.rb:10-21`). **Não há etapa de validação** (ver GAP 5).
- **API** (`config/routes.rb:482-487`):
  - `GET ai_agent_config`
  - `PUT ai_agent_config/draft`
  - `POST ai_agent_config/publish`
- **Nenhuma chave no config:**
  - O schema e os params permitidos não têm chave (`ai_agent_configs_controller.rb:28-37`).
  - A chave vem só de `InstallationConfig` `CAPTAIN_OPEN_AI_API_KEY` (`lib/llm/config.rb:43-45`).
- **Runtime** lê só a versão publicada, e só se `enabled` (`turn_orchestrator.rb:58-68`).
- **Campos realmente usados em runtime:**
  - Nas instruções do LLM: `role, objective, persona, tone, instructions, service_rules` (`model_invoker.rb:74-77`).
  - `forbidden_subjects`, no guardrail de entrada (`input_guardrail.rb:37-41`).
  - `required_qualification_fields`, no gate de geração de proposta (`generate_service.rb:39-54`).
  - `model_selection`, via `ModelResolver` (`model_resolver.rb:15-32`).
  - `name`, como nome do `AgentBot` remetente (`response_sender.rb:59-61`).
  - `enabled`.
  - `require_proposal_approval`.
- **Campos gravados e nunca lidos em runtime:**
  - `service_hours`, `response_limits`, `transfer_criteria`, `restricted_information`, `qualification_playbook` aparecem só no controller/model (grep em `app/services app/jobs`).
  - `model_provider` é lido do *resultado* (`response_sender.rb:49`), não do config.
- **Nenhuma tela edita `require_proposal_approval`:** o campo não está no `emptyForm` de `AgentCenter.vue:29-47`.

### 2.2 LLM
- `config/llm.yml:205-215`: `scansolo_agent_response` com modelos [gpt-4.1-mini, gpt-4.1, gpt-5.1, gpt-5.2], default gpt-4.1-mini, `internal: true`.
- `config/llm.yml:219-223`: `scansolo_knowledge_embedding` com `text-embedding-3-small`.
- **Resolução:** `ModelResolver` → `Llm::FeatureRouter.resolve` (`model_resolver.rb:15-24`; precedência em `lib/llm/feature_router.rb:23-44`). Um `model_selection` inválido cai no default em silêncio (`model_resolver.rb:30-32`).
- **Invocação:** RubyLLM direto (`model_invoker.rb:57-72`). Erros de provider viram `failure_reason` (`:36-39`). ScanSolo não usa o SDK `ai-agents` do Captain (`config/initializers/ai_agents.rb:5-23`).
- **Telemetria por turno:** provider, modelo, tokens, `failure_reason`, `context_snapshot` e `correlation_id` (`app/models/scan_solo/ai_turn.rb:3-30`; escrita em `response_sender.rb:47-57`). As colunas `latency_ms`, `cost_estimate` e `knowledge_evidence` existem, mas nunca são escritas.

### 2.3 Knowledge / RAG
- **Fontes:** `ScanSolo::KnowledgeSource` com tipos `document/faq/company_info`, `has_one_attached :file` (`app/models/scan_solo/knowledge_source.rb:26-41`).
- **Chunks:** `ScanSolo::KnowledgeChunk` com `vector(1536)` e `has_neighbors` (`knowledge_chunk.rb:25-32`). Não há índice HNSW/ivfflat, por decisão (`db/migrate/20260918030002_*.rb:6-11`).
- **Ingestão síncrona na request:**
  - Divide por parágrafos e quebra em ~500 caracteres.
  - Faz um embedding por chunk.
  - Destrói e recria os chunks numa transação (`ingestion_service.rb:19-46`; `sources_controller.rb:21,40`).
- **Recuperação** (`retrieval_service.rb:26-52`):
  - Cosine, top_k 5, só fontes `enabled`.
  - Devolve `source_id` para atribuição.
  - Uma falha devolve `{results: [], failure_reason}`.
- **Operação:**
  - Reindex manual: `POST knowledge/sources/:id/reindex`.
  - Desabilitar exclui a fonte da recuperação.
  - Delete remove em cascata.
  - Simulador: `POST knowledge/retrieval_tests`.
- **Ausente:**
  - URL e crawl de site.
  - Parse de PDF: o arquivo anexado é ignorado, porque a ingestão lê só `content` (`ingestion_service.rb:20`).
  - Status e erro de indexação.
  - Job assíncrono.
  - Reingestão automática no update.
- **Crítico:** o contexto recuperado não entra no prompt (§0 #1).

### 2.4 Fluxo inbound (Widget / WhatsApp / qualquer inbox)
- `ScanSolo::ConversationListener` está registrado no `AsyncDispatcher` (`app/dispatchers/async_dispatcher.rb:23`).
- Filtros: `incoming?` e `scansolo_enabled?` (`conversation_listener.rb:12-13`).
- Faz a contabilidade do pipeline se já houver oportunidade (`:22-29`).
- Enfileira `AiTurnJob` na fila medium (`app/jobs/scan_solo/ai_turn_job.rb:14-24`).
- **Agnóstico de canal:** não há filtro por inbox ou canal. O Website widget é atendido pelo mesmo agente, com o mesmo RAG e o mesmo handoff.
- **Dedupe** por `message_id`, com índice único (`db/migrate/20260918040000_*.rb:18`). Não há debounce nem lock por conversa.

### 2.5 WhatsApp (nativo, upstream)
- **Webhook:** `app/controllers/webhooks/whatsapp_controller.rb`.
  - Verify token por canal (`:28-32`).
  - HMAC `X-Hub-Signature-256` (`app/controllers/concerns/meta_token_verify_concern.rb:21-38`).
  - A verificação é opcional para `whatsapp_cloud` sem app secret no canal (`whatsapp_controller.rb:45-51`).
- **Status** sent/delivered/read/failed, com `external_error` (`app/services/whatsapp/incoming_message_base_service.rb:51-67`).
- **Janela de 24h:** aplicada ao texto livre pelo envio nativo (`send_on_whatsapp_service.rb:15-17`).
- **Sem Evolution e sem cliente paralelo** (grep vazio em `app lib config enterprise`). O ScanSolo envia só via `conversation.messages.create!`.

### 2.6 Templates Meta
- **Sync nativo:**
  - `WhatsappCloudService#sync_templates` (`app/services/whatsapp/providers/whatsapp_cloud_service.rb:35-45`).
  - Scheduler a cada 3h (`app/jobs/channels/whatsapp/templates_sync_scheduler_job.rb:5-11`).
  - Grava `channel_whatsapp.message_templates` e `message_templates_last_updated`.
- **Mapeamento por convenção de nome:** `scansolo_cadence_<stage>_v<version>_step<N>` (`app/models/scan_solo/cadence_definition.rb:50-52`), mais `scansolo_proposal_send` (`callback_handler.rb:10`).
- **Guard de disponibilidade:** exige nome igual e status `approved` (`template_availability_guard.rb:24-50`).
  - Ignora o idioma.
  - Não roda para `scansolo_proposal_send`.
  - Canais que não são WhatsApp passam sempre (`:45`).
- **Parâmetros:**
  - Idioma fixo `pt_BR` (`native_template_sender.rb:52`).
  - Nenhum parâmetro é passado (`cadence_due_attempt_job.rb:46-49`).
- **Motivo do skip** (missing/rejected/paused) é descartado e não há coluna para ele (`cadence_due_attempt_job.rb:36-38`).
- **Não há UI de templates ScanSolo.**

### 2.7 Cadências
- **Tabelas:**
  - `scan_solo_cadence_definitions`: unique `(stage, version)`.
  - `scan_solo_cadence_enrollments`: unique `(opportunity_id, cadence_definition_id)`.
  - `scan_solo_cadence_attempts`: unique `(enrollment_id, step)`.
- **Seed** (`db/seeds/scansolo_cadence_definitions.rb:6-15`):
  - `novo_lead` [2,24,48,96]h, sem tentativa inicial imediata.
  - `em_contato` [24..120] (5 tentativas).
  - `em_qualificacao` [24..168] (7 tentativas).
  - `proposta_enviada` [24,72,168].
  - **O seed não é carregado por `db/seeds.rb`** (grep `scansolo` em `db/seeds.rb` vazio).
- **Cron:** a cada 5 min (`config/schedule.yml:79-84`) → `CadenceDueAttemptJob` (`app/jobs/scan_solo/cadence_due_attempt_job.rb:16-55`).
  - Faz lock de linha e rechecagem.
  - Janela 09–20 America/Sao_Paulo, 7 dias (`sending_window.rb:5-23`).
  - Fora da janela, reagenda para as 09:00.
- **Paradas conectadas:**
  - Qualquer transição de estágio (`stage_transition_service.rb:38` → `stop_recalculate_policy.rb:33-42`).
  - Takeover (`takeover_service.rb:41`).
  - Pause/resume/cancel manual (`cadence_enrollments_controller.rb:31-47`, `lifecycle_service.rb:23-67`).
- **Não conectado:**
  - Enroll automático ao entrar em novo_lead/em_contato/em_qualificacao.
  - `ReplyCompletenessDetector`, que não tem chamador.
  - Opt-out.
  - Checagem de `ai_control_state` ou `scansolo_enabled` no job.
- **Estado "sent" gravado antes da confirmação da Meta** (`cadence_due_attempt_job.rb:50`).

### 2.8 Pipeline
- **8 estágios** (`app/models/scan_solo/pipeline_opportunity.rb:48-57`). Uma oportunidade por conversa (`:59`).
- **`StageTransitionService`** (`stage_transition_service.rb:21-68`):
  - Bloqueia estágio desconhecido e saída de ganho/perdido.
  - `negociacao` exige `authorized`, mas o controller sempre passa `true` (`pipeline_opportunities_controller.rb:34`).
  - Não há matriz de transições.
- **Timeline** append-only `PipelineStageEvent` (`pipeline_stage_event.rb:18-31`).
- **Transições automáticas em produção:**
  - novo_lead→em_contato na primeira inbound (`inbound_message_transition_rule.rb:14-25`).
  - →proposta_enviada após envio (`success_handler.rb:29-33`).
  - Ambas dependem de uma oportunidade existir, e **nada a cria**.

### 2.9 Handoff
- **Estados:** ai_active/handoff_requested/awaiting_human/human_active/paused/closed (`conversation_extension.rb:20-27`). Só `ai_active` permite a IA (`eligibility_guard.rb:18-20`).
- **Takeover:** nota privada, `human_active`, auditoria e cancelamento das cadências (`takeover_service.rb:26-44`).
- **Retorno à IA:** `ai_active` e auditoria (`return_to_ai_service.rb:15-30`).
- **Rotas** `routes.rb:508-512`: `GET control_state`, `POST handoff`, `POST return_to_ai`.
- **Política:** agente atribuído ou admin (`handoff_policy.rb:6-28`).
- **Ausente:**
  - Endpoints pause/close/reopen.
  - Atribuição nativa (`assignee`).
  - Pausa ao responder como humano.
  - `HandoffControlBanner.vue` montado: o componente existe mas não é usado fora do seu spec.
- A nota fixa `proposal_status = 'não aplicável'` (`handoff_service.rb:119-124`).

### 2.10 Propostas / Make
- **Modelos:** `Proposal` e `ProposalVersion` (generating/generated/approved/sent/failed; correlation ids únicos, `db/migrate/20260918070001_*:21-27`).
- **Fluxo:** generate (exige qualificação), approve, send (exige aprovação se requerida) (`generate_service.rb:39-54`, `approve_service.rb:18-27`, `send_service.rb:24-57`).
- **Provider padrão `MockProvider`.** O controller não sobrescreve (`proposals_controller.rb:25,45-48`).
- **`OutboundRequestService`** (`make/outbound_request_service.rb:35-86`):
  - Credentials `scan_solo.make.scenario_url` e `scan_solo.make.secret`.
  - Bearer e `X-Idempotency-Key`.
  - Timeout de 10s.
  - **Sem chamador.**
- **Callback** `POST /webhooks/scan_solo/make` (`routes.rb:737`):
  - HMAC `X-Make-Signature`, com `scan_solo.make.inbound_signing_secret` (`callback_verifier.rb:90-96`).
  - JSON schema.
  - Match com `MakeRequest`.
  - Índice único em `correlation_id`.
  - rack-attack 60/min.
  - **Só atualiza `MakeRequest.status`** (`make_controller.rb:39-49`).
- **Retry e dead letter nominais:** `RetryPolicy` sem rota, `retry_count>=3` inalcançável.
- **UI:** `Proposals.vue` com aprovar e enviar. Envio sem confirmação. `failure_reason` não renderizado.
- **Preço:** nenhum cálculo no repo. A IA não gera preço, porque o regex de saída bloqueia (`output_validator.rb:10-44`).

### 2.11 LEXUS / cutover
- **Só documentação:**
  - `docs/migration/SCANSOLO_LEXUS_CUTOVER_DESIGN.md:3-9,306-314` ("none of that script exists yet").
  - `docs/runbooks/PRODUCTION_CUTOVER.md`: regra de dono único `:74-92`, 21 passos `:94-116`, abort `:118-133`, rollback `:135-148` sem comandos.
- **Sem código de importação** (grep `lexus` vazio em `app lib db config`).
- **Sem kill switch de outbound.** Os únicos controles são `Account#scansolo_enabled` e `AiAgentConfig#enabled`.

### 2.12 Segurança
- **Flag no backend:** `BaseController` com `prepend_before_action :ensure_scansolo_enabled` → 404 (`base_controller.rb:5-11`), antes da autenticação.
- **Flag no frontend:** só o sidebar. As rotas não checam a flag (`FE/index.js:13-15`).
- **Escopo por conta** em todos os controllers ScanSolo (ver audit A §1.5). Pundit com base deny-all (`app/policies/scan_solo/application_policy.rb:12-38`).
- **Autorização frouxa:**
  - `AiAgentConfigPolicy` e `KnowledgeSourcePolicy` retornam `true` para tudo. Qualquer agente publica o config e altera a base.
  - Contraste: `cadence_enrollment_policy.rb:14-16` e `handoff_policy.rb:16-20` exigem admin.
- **Rate limit** só no callback Make (`config/initializers/rack_attack.rb:345-353`).
- **Redação global de logs** via `PromptRedactor` (`config/initializers/scansolo_log_redaction.rb:16-27`). O regex `\b[A-Za-z0-9_\-]{32,}\b` também apaga UUIDs (`prompt_redactor.rb:16`).
- **Auditoria** (`AuditLogger.record!`) só em executor de ações, takeover e return_to_ai. Publish, knowledge e flag não são auditados.
- **Segredos:** nenhum segredo ScanSolo commitado. As composes usam `${VAR}`.
- **Isolamento:** `spec/lib/scansolo_no_enterprise_dependency_spec.rb:9-19` proíbe `Captain::` em `app/**/scan_solo/**`.
- **Flag `scansolo_enabled`:** sem UI no Super Admin nem rake task. Só console.

### 2.13 Frontend (6 módulos)
- **Rotas:** `FE/index.js:19-26`, subrotas `:43-54`. A fonte única dos módulos é `FE/scansoloModules.js:5-42`.
- **Stores:** 7 stores Pinia (`ST/*.js`).
- **Convenções:** todos os componentes usam `<script setup>` e só Tailwind.
- **Scroll quebrado em todas as telas:** `<main ... overflow-hidden>` (`Dashboard.vue:142-143`) monta as rotas ScanSolo direto, sem wrapper com `overflow-y-auto`.
  - Raízes afetadas: `AgentCenter.vue:115`, `KnowledgeCenter.vue:71`, `FollowUps.vue:21`, `Proposals.vue:36`, `Executions.vue:15`, `TurnEvidenceViewer.vue:30`, `OpportunityDetail.vue:42`, `KanbanBoard.vue:66`.
- **i18n:**
  - Só existe `en/scansolo.json`, com valores em **português**. Não há `pt_BR/scansolo.json`.
  - A instância vue-i18n é criada com `locale: 'en'` e sem `fallbackLocale` explícito (`app/javascript/entrypoints/dashboard.js:37-41`). Usuários pt_BR dependem do fallback implícito do vue-i18n; isso não foi verificado em runtime.
  - 10 chaves quebradas por `toUpperCase()`: MODELPROVIDER, MODELSELECTION, TRANSFERCRITERIA, RESPONSELIMITS, SERVICEHOURS, SERVICERULES, QUALIFICATIONPLAYBOOK, REQUIREDQUALIFICATIONFIELDS, RESTRICTEDINFORMATION, FORBIDDENSUBJECTS.
- **Agent Center:**
  - Badge publicado/não publicado (`AgentCenter.vue:120-134`).
  - Aviso estático de draft (`:137-143`).
  - Confirmação de publish (`:211-239`).
  - Provider e model são `<input type="text">` livres (`:9-20,155-165`).
  - Não tem: seções, ações sticky, validação, aviso de alterações não salvas, toasts e botões desabilitados durante a requisição.
- **Cross-cutting:**
  - Sem loading (nenhum `uiFlags` usado).
  - Sem erro nem toast (nenhum `useAlert`).
  - Timestamps em ISO cru.
  - IDs técnicos visíveis: `ownerId`, `sourceId`, correlation ids, JSON cru.
  - Sem filtros nem paginação.
  - Delete de knowledge, cancel de follow-up e envio de proposta sem confirmação.
  - Rotas órfãs: detalhe da oportunidade e evidência do turno.

### 2.14 Deploy
- **`docker-compose.production.yaml`:**
  - Build local `scansolo-chatwoot:${SCANSOLO_IMAGE_TAG:-local}` (`:5-8`, commit 4af19b0bb).
  - Portas em 127.0.0.1 (`:19,44,61`).
  - Imagem `pgvector/pgvector:pg16` (`:41`).
  - Redis com senha (`:56`).
  - **`POSTGRES_PASSWORD=` vazio (`:51`).**
  - Sem healthchecks.
  - `version: '3'` obsoleto.
- **`docker/Dockerfile`:** `RUN git rev-parse HEAD > /app/.git_sha` (`:90`), copiado ao estágio final (`:151`).
  - Não há build arg `GIT_SHA`.
  - `.git` não está em `.dockerignore`.
  - `config/initializers/git_sha.rb` lê `.git_sha`.
- **Overlay `docker-compose.scansolo.yaml`:**
  - Healthchecks e rotação de log.
  - Profiles `self-hosted-storage` (MinIO), `reverse-proxy` (Caddy em 80/443) e `backup` (pg_dump).
- **`docs/architecture/SCANSOLO_DEPLOYMENT.md`:**
  - Instrui `-f docker-compose.yaml -f docker-compose.production.yaml -f docker-compose.scansolo.yaml` (`:40-41,110-111,134-135,148-149`), o que mistura o compose de dev.
  - Afirma imagem `chatwoot/chatwoot:latest` (`:23`), já desatualizada.
- **Imagens não fixadas:** `redis:alpine`, `minio/minio:latest`, `caddy:2-alpine`, `postgres:16-alpine`, `node:24-alpine`.

### 2.15 Observabilidade
- **`ScanSolo::AiTurn`:** status pending/suppressed/succeeded/failed e `failure_reason`, visível em `GET scan_solo/ai_turns[/:correlation_id]` e em `TurnEvidenceViewer.vue`.
- **`ScanSolo::AuditEvent`:** append-only (`audit_event.rb:22-34`).
- **`GET scan_solo/executions`:** cadências, dead letters Make, callbacks não aplicados e auditoria, com limite de 100 (`executions_controller.rb:10-55`).
- **Ausente:**
  - Latência e custo.
  - Falhas de webhook Meta na UI ScanSolo.
  - Métricas de template send/fail.
  - Contagem de handoffs.
  - Integração com `ChatwootExceptionTracker`/Sentry no código ScanSolo.

---

## 3. Inventário de testes

Contagens por grep (os testes não foram executados).

**Ruby: 75 arquivos** (73 specs + `spec/support/scansolo_test_mode.rb` + `spec/support/scansolo_webmock_enforcement.rb`).

| Área | Arquivos | Destaques |
|---|---|---|
| models | 9 | ai_agent_config (5), knowledge_source (4), knowledge_chunk (2), cadence_definition (5), pipeline_opportunity (5), proposal_version (6), conversation_extension (11), audit_event (4) |
| services | 44 | ai_turn 8, cadence 7, proposal 6, actions 4, knowledge 4, pipeline 3, ai_agent 2, make 2, handoff 1, messaging 1, test_mode 1, top-level 2 |
| requests | 10 | ai_agent_configs (6), ai_turns (3), knowledge sources (7), retrieval_tests (3), cadence_enrollments (6), pipeline_opportunities (6), proposals (7), executions (5), handoff (9), `webhooks/scan_solo/make_controller_spec.rb` (12) |
| controllers / policies / jobs | 1 / 2 / 2 | base_controller (4); application_policy (4), coverage_audit (6); ai_turn_job (5), cadence_due_attempt_job (4) |
| integration | 2 | `full_test_mode_spec.rb` (22), `acceptance_traceability_spec.rb` (6) |
| db / lib | 1 / 5 | `scansolo_migrations_spec.rb` (34); branding, deployment doc, dispatcher reuse, migration design doc, no-enterprise-dependency |

**Frontend: 11 specs, 48 casos.**
- navigation (3), AgentCenter (6), TurnEvidenceViewer (3), KanbanBoard (3), OpportunityDetail (3), KnowledgeCenter (7), FollowUps (5), Proposals (6), Executions (5).
- `en/specs/scansolo.spec.js` (2) valida só `SIDEBAR`.
- HandoffControlBanner (5).
- **Todos os specs de componente mockam `t: key => key`**, então não conseguem detectar chave i18n inexistente.

**Sem cobertura:**
- Prompt contém RAG.
- Crawler e URL.
- PDF.
- Rajada de mensagens.
- Captain e ScanSolo juntos.
- Humano responde sem takeover.
- Mensagem sem texto (só anexo).
- Rate limit ScanSolo.
- Auditoria de publish e knowledge.
- Rotação de chave.
- Callback Make → ProposalVersion (o caminho não existe).
- Criação de oportunidade.
- Import LEXUS.
- Completude i18n.
- Compose de produção (`scansolo_deployment_doc_spec.rb:50-59` valida só dev+overlay).
- E2E (Cypress/Playwright) para ScanSolo.
- Spec unitário de `TakeoverService`/`ReturnToAiService`, `SendingWindow`, `CadenceSignalAction`, `HandoffAction`, `StageTransitionAction`.
