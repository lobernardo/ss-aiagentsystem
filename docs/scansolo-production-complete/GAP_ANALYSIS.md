# ScanSolo Production Complete — Análise de Gaps

Gerado em 2026-09-23 a partir do commit 4af19b0bb (branch feat/scansolo-production-complete). Documento factual — não implementa nada.

Documentos relacionados: [CURRENT_STATE](CURRENT_STATE.md) · [ARCHITECTURE_MAP](ARCHITECTURE_MAP.md) · [DECISIONS_REQUIRED](DECISIONS_REQUIRED.md) · [RISK_REGISTER](RISK_REGISTER.md)

**Status:**
- **Implementado:** atende o requisito com evidência.
- **Parcial:** existe, mas falta parte do requisito.
- **Ausente:** não existe no repo.
- **Quebrado:** existe, mas está defeituoso em produção.

**Tamanho:**
- **S:** até ~1 dia.
- **M:** 2–4 dias.
- **L:** 1 semana ou mais.

As estimativas são indicativas.

---

## 1. Tabela por área (22 áreas do escopo)

### Área 1 — Scroll e layout do Agent Center
| Requisito | Status | Evidência | Gap | Tam. |
|---|---|---|---|---|
| Scroll vertical em Agent Center e demais telas | Quebrado | `Dashboard.vue:142-143` (`overflow-hidden`); raízes `AgentCenter.vue:115`, `KnowledgeCenter.vue:71`, `FollowUps.vue:21`, `Proposals.vue:36`, `Executions.vue:15`, `TurnEvidenceViewer.vue:30`, `OpportunityDetail.vue:42`, `KanbanBoard.vue:66` | Rotas montadas direto no `<main>` sem wrapper `h-full overflow-y-auto`. Padrões nativos: `SettingsWrapper.vue:22-24`, `components-next/captain/PageLayout.vue:122,213` | S |
| Layout responsivo | Parcial | `TurnEvidenceViewer.vue:54` (`grid-cols-3` fixo); linhas sem wrap em `KnowledgeCenter.vue:142,160` | Ajustes de responsividade | S |

### Área 2 — i18n pt-BR e chaves cruas
| Requisito | Status | Evidência | Gap | Tam. |
|---|---|---|---|---|
| Nenhuma chave crua | Quebrado | `AgentCenter.vue:157,169,181` (`field.toUpperCase()`) vs `en/scansolo.json:76-90` (`MODEL_PROVIDER`…) | 10 chaves quebradas: MODELPROVIDER, MODELSELECTION, TRANSFERCRITERIA, RESPONSELIMITS, SERVICEHOURS, SERVICERULES, QUALIFICATIONPLAYBOOK, REQUIREDQUALIFICATIONFIELDS, RESTRICTEDINFORMATION, FORBIDDENSUBJECTS | S |
| Locale pt-BR | Ausente | não há `pt_BR/scansolo.json`; `en/scansolo.json` contém português (ex. `:76`); `entrypoints/dashboard.js:37-41` sem `fallbackLocale` | Estratégia conflita com a regra do CLAUDE.md (só `en.json`). Ver D-19 | M |
| Teste de completude i18n | Ausente | specs mockam `t: key => key` (ex. `AgentCenter.spec.js:14-15`); `en/specs/scansolo.spec.js:5-26` cobre só `SIDEBAR` | Nenhum teste detecta chave inexistente | S |

### Área 3 — UX do Agent Center
| Requisito | Status | Evidência | Gap | Tam. |
|---|---|---|---|---|
| Seções (Identidade/Modelo/Comportamento/Qualificação/Segurança/Handoff/Horário/Proposta) | Ausente | `AgentCenter.vue:9-27`: três listas planas (TEXT/TEXTAREA/ARRAY) | Reorganizar o formulário | M |
| Ações sticky | Ausente | `AgentCenter.vue:115-239` | — | S |
| Indicadores de draft/publicado | Parcial | badge `:120-134`; aviso estático `:137-143` | Não compara o draft com a versão publicada | S |
| Validação | Ausente | `ai_agent_config.rb:59` (só unicidade do draft); `publish_service.rb:10-21` sem checagem | Publicar config vazio é possível | M |
| Dropdown de provider e de modelo a partir de `config/llm.yml` | Ausente | inputs texto `AgentCenter.vue:9-20,155-165`; `model_provider` ignorado (`model_resolver.rb:20`); padrão reutilizável em `captain/preferences_controller.rb:19-22` | Modelo inválido cai no default em silêncio (`model_resolver.rb:30-32`) | S |
| Aviso de alterações não salvas | Ausente | nenhum `beforeunload`/`onBeforeRouteLeave` | — | S |
| Sem publicação acidental | Implementado | confirmação `AgentCenter.vue:95-109,211-239` | Botões não ficam desabilitados durante a requisição (`ST/aiAgentConfig.js:19-20` não usado) | S |
| Feedback de salvar/publicar | Ausente | `AgentCenter.vue:72-93,106-109` sem try/catch nem toast | — | S |
| `require_proposal_approval` editável | Ausente | não está em `emptyForm` (`AgentCenter.vue:29-47`) | Seção "Proposta" | S |

### Área 4 — Compose de produção
| Requisito | Status | Evidência | Gap | Tam. |
|---|---|---|---|---|
| `POSTGRES_PASSWORD=${POSTGRES_PASSWORD}` | Quebrado | `docker-compose.production.yaml:51` (`POSTGRES_PASSWORD=`) | Drift com a VPS (correção manual, reportado pelo usuário) | S |
| Build reproduzível | Parcial | build local `:5-8`; imagens flutuantes `redis:alpine` `:54`, `pgvector/pgvector:pg16` `:41`, `node:24-alpine` `Dockerfile:2`; `apk add` sem pin | Fixar tags ou digests | S |
| `GIT_SHA` build arg → `/app/.git_sha` | Ausente | `Dockerfile:90` usa `git rev-parse HEAD`; `.git` não está em `.dockerignore` | Falha em worktree ou tarball | S |
| Postgres/Redis/Rails só em localhost | Implementado (arquivo isolado) / Quebrado (comando documentado) | `docker-compose.production.yaml:19,44,61`; `SCANSOLO_DEPLOYMENT.md:40-41` empilha `docker-compose.yaml` (portas públicas `:37,89,105`, bind mount `:25`, vite, mailhog) | Corrigir o comando e a doc; adicionar lint da combinação prod (`scansolo_deployment_doc_spec.rb:50-59` só valida dev+overlay) | S |
| Healthchecks e `depends_on` healthy | Parcial | só no overlay `docker-compose.scansolo.yaml:28-61`, sem `condition:` | — | S |

### Área 5 — Agente de IA
| Requisito | Status | Evidência | Gap | Tam. |
|---|---|---|---|---|
| Draft → validate → publish | Parcial | `publish_service.rb:10-21` | Falta a etapa de validação | M |
| `Llm::FeatureRouter` + OpenAI | Implementado | `model_resolver.rb:15-24`, `model_invoker.rb:57-72`, `config/llm.yml:205-215` | — | — |
| Nenhuma chave no `AiAgentConfig` | Implementado | `ai_agent_configs_controller.rb:28-37`; `lib/llm/config.rb:43-45` | — | — |
| Health/status sem expor segredo | Ausente | rotas `routes.rb:482-487` | Endpoint: chave configurada (bool), modelo, fontes indexadas, último turno | S |
| Todos os campos de comportamento usados | Parcial | `model_invoker.rb:74-77`; `service_hours`, `response_limits`, `transfer_criteria`, `restricted_information`, `qualification_playbook` sem leitor em runtime | Ligar os campos ao prompt e às regras | M |
| Contexto (RAG, contato, pipeline) no prompt | Quebrado | `turn_orchestrator.rb:154-157` | Só o histórico é enviado | S |
| Turno nunca fica `pending` | Quebrado | `model_invoker.rb:16`, `turn_orchestrator.rb:47-56` | Exceção genérica + retry que colide com o dedupe | S |
| Troca de chave sem restart | Parcial | `lib/llm/config.rb:11-16` (memoizado) | Documentar o restart ou reinicializar | S |

### Área 6 — RAG
| Requisito | Status | Evidência | Gap | Tam. |
|---|---|---|---|---|
| Ingestão, chunking, embeddings, pgvector, recuperação | Implementado | `ingestion_service.rb:19-46`, `embedding_service.rb:18-23`, `retrieval_service.rb:26-52` | Sem índice ANN (`20260918030002:6-11`) | — |
| Reindex, desativar, excluir | Implementado | `sources_controller.rb:26-42`, `retrieval_service.rb:41` | Update de `content` não reingere | S |
| Status, erros e reprocessamento | Ausente | migration `20260918030000:3-13`; `_source.json.jbuilder:1-11` | Não há `status`, `last_error` nem `indexed_at`; ingestão síncrona deixa fonte com 0 chunks em caso de falha | M |
| Auditoria de mudanças na base | Ausente | `AuditLogger.record!` só em 3 lugares | — | S |
| Atribuição de fonte | Parcial | `source_id` no resultado; `knowledge_evidence` nunca escrito | — | S |
| Tipo texto | Implementado | `document/faq/company_info` (`knowledge_source.rb:38`) | — | — |
| Tipo PDF | Quebrado | arquivo anexado e ignorado (`ingestion_service.rb:20`); nenhum gem de PDF no OSS | Ver D-13 | M |
| Tipo URL e crawl de site com allowlist, profundidade, canonicalização, dedup, SSRF, reindex manual | Ausente | grep vazio | Construir sobre `lib/safe_fetch.rb` e `ssrf_filter`. Ver D-11/D-12 | L |
| Job de indexação assíncrono | Ausente | `app/jobs/scan_solo/` tem só 2 jobs | — | M |

### Área 7 — Widget do site
| Requisito | Status | Evidência | Gap | Tam. |
|---|---|---|---|---|
| Mesmo agente e mesmo RAG no widget | Parcial | listener agnóstico de canal (`conversation_listener.rb:10-18`) | Herda o bug do RAG fora do prompt. A existência do inbox widget e a origem do site são desconhecidas (D-10) | S |
| Handoff no widget | Parcial | mesmos endpoints de handoff | Mesmas lacunas da Área 12 | — |
| Restrição por inbox | Ausente | nenhuma checagem de inbox | Toda inbox da conta aciona a IA (inclui e-mail). Ver D-10 | S |

### Área 8 — WhatsApp Cloud API nativo
| Requisito | Status | Evidência | Gap | Tam. |
|---|---|---|---|---|
| Só nativo, sem Evolution e sem cliente paralelo | Implementado | grep `evolution` vazio; envio via `messages.create!` | — | — |
| Webhook e status sent/delivered/read/failed | Implementado (nativo) | `incoming_message_base_service.rb:51-67` | O status não volta para `CadenceAttempt` nem para `AiTurn` | M |
| Assinatura obrigatória | Parcial | `whatsapp_controller.rb:45-51` | Canal `whatsapp_cloud` sem app secret no canal aceita webhook sem assinatura | S |
| Dono único vs LEXUS | Ausente | nenhum kill switch (grep) | Ver Área 15 | M |

### Área 9 — Templates Meta
| Requisito | Status | Evidência | Gap | Tam. |
|---|---|---|---|---|
| Sync | Implementado (nativo) | `whatsapp_cloud_service.rb:35-45`, `templates_sync_scheduler_job.rb:5-11` | — | — |
| Mapeamento por tentativa de cadência | Parcial | convenção de nome `cadence_definition.rb:50-52` | Sem mapeamento explícito; idioma fixo `pt_BR` (`native_template_sender.rb:52`); parâmetros vazios (`cadence_due_attempt_job.rb:46-49`) | M |
| UI (nome, idioma, categoria, status, params, último sync, disponibilidade) | Ausente | — | — | M |
| Nunca enviar template ausente, rejeitado ou pausado | Parcial | `template_availability_guard.rb:24-50` (exige `approved`) | Ignora idioma; não cobre `scansolo_proposal_send` | S |
| Motivo auditado | Ausente | motivo descartado em `cadence_due_attempt_job.rb:36-38`; sem coluna | — | S |

### Área 10 — Cadências
| Requisito | Status | Evidência | Gap | Tam. |
|---|---|---|---|---|
| Novo Lead: inicial, +2h, +24h, +48h, +96h | Parcial | seed `[2,24,48,96]` (`db/seeds/scansolo_cadence_definitions.rb:7`) | Falta a tentativa inicial. Ver D-06 | S |
| Em Contato 5×24h / Em Qualificação 7×24h | Implementado (seed) | `:8-9` | O seed não é carregado por `db/seeds.rb` | S |
| Janela 09–20 America/Sao_Paulo, 7 dias | Implementado | `sending_window.rb:5-23` | Sem spec dedicado | — |
| Idempotência | Implementado | índices únicos, `lock.find` (`cadence_due_attempt_job.rb:23-25`), `attempt_evidence_recorder.rb:31-40` | — | — |
| Enroll automático por estágio | Ausente | `EnrollmentService` só em `success_handler.rb:39` e `lifecycle_service.rb:18` | — | M |
| Parar ao receber resposta; recalcular em resposta parcial | Ausente | `ReplyCompletenessDetector` sem chamador | — | M |
| Checagens antes do envio (handoff, flag, opt-out) | Ausente | `cadence_due_attempt_job.rb:22-42` | — | S |
| Pausa temporária não consome tentativas | Quebrado | `automation_disabled` → `skipped` permanente (`:35-38`) | — | S |
| "sent" confiável | Quebrado | `record_sent!` antes do status Meta (`:50`) | — | M |
| Re-enroll após cancelamento | Quebrado | unique `(opportunity, definition)` + `enrollment_service.rb:18-25` | — | S |

### Área 11 — Pipeline
| Requisito | Status | Evidência | Gap | Tam. |
|---|---|---|---|---|
| 8 estágios | Implementado | `pipeline_opportunity.rb:48-57` | — | — |
| Criação de oportunidade | Ausente | grep sem criação; rotas `routes.rb:463` | Nada inicia o pipeline. Ver D-07 | M |
| Transições auditadas | Implementado | `PipelineStageEvent` readonly (`pipeline_stage_event.rb:18-31`) | Não gera `AuditEvent` | — |
| Sem transição automática indevida | Parcial | só estágio terminal e `negociacao` são protegidos; controller passa `authorized: true` (`pipeline_opportunities_controller.rb:34`) | Sem matriz de transições. Ver D-08 | S |
| UI | Parcial | Kanban otimista (`KanbanBoard.vue:43-56`) | Sem link para o detalhe, `ownerId` cru, ISO cru, revert silencioso | S |

### Área 12 — Handoff
| Requisito | Status | Evidência | Gap | Tam. |
|---|---|---|---|---|
| IA → humano | Parcial | `takeover_service.rb:26-44` | Só manual via API; `HandoffAction` inalcançável | M |
| Atribuição | Ausente | takeover não define `assignee` | — | S |
| Pausar IA | Implementado (via estado) | `eligibility_guard.rb:18-20` | Sem recheck antes do envio | S |
| Pausar cadência | Implementado | `takeover_service.rb:41` | Retorno à IA não re-inscreve | S |
| Ações pausar, encerrar, reabrir, assumir, devolver à IA | Parcial | só assumir e devolver (`routes.rb:508-512`) | pausar, encerrar e reabrir ausentes | M |
| Nunca respostas simultâneas | Quebrado | `conversation_listener.rb:12` ignora saída humana; sem lock por conversa; Captain | Auto-takeover ou lock | M |
| UI na conversa | Ausente | `HandoffControlBanner.vue` não montado | — | S |

### Área 13 — Propostas via Make
| Requisito | Status | Evidência | Gap | Tam. |
|---|---|---|---|---|
| Preço determinístico; a IA nunca inventa preço | Parcial | a IA é bloqueada por regex (`output_validator.rb:10-44`); nenhum cálculo de preço no repo | Preço hoje só vem do `MockProvider` (1500 BRL). Ver D-04 | M |
| Integração real com Make | Quebrado | `MockProvider` padrão (`generate_service.rb:12`, `send_service.rb:10`); `OutboundRequestService` sem chamador | — | L |
| Callback autenticado com correlation id e idempotência | Parcial | HMAC + schema + unique (`callback_verifier.rb:90-96`, `make_controller.rb:11-31`) | Não aplica em `ProposalVersion`; rejeição queima o id (`make_controller.rb:16,35-37,51-59`) | M |
| Retry, dead letter e timeout | Parcial | timeout 10s; `RetryPolicy` sem rota; `retry_count>=3` inalcançável | — | M |
| Visibilidade de falha na UI e reprocessamento manual | Ausente | `failure_reason` não renderizado em `Proposals.vue` | — | S |
| Aprovação | Implementado | `approve_service.rb:18-27`, `proposal_version.rb:68-71` | Política de quem aprova. Ver D-05 | — |
| Envio + estágio Proposta Enviada | Implementado (com mock) | `callback_handler.rb:55-66`, `success_handler.rb:17-40` | Sem confirmação na UI; template não validado | S |

### Área 14 — Ferramenta de import LEXUS
| Requisito | Status | Evidência | Gap | Tam. |
|---|---|---|---|---|
| Dry-run, relatório criado/atualizado/ignorado/erro, sem duplicatas | Ausente | `SCANSOLO_LEXUS_CUTOVER_DESIGN.md:306-314`; grep `lexus` vazio | Fonte e mapeamento desconhecidos (D-14) | L |

### Área 15 — Cutover
| Requisito | Status | Evidência | Gap | Tam. |
|---|---|---|---|---|
| Checklist de dono único + rollback | Parcial (doc) | `PRODUCTION_CUTOVER.md:74-148`; rollback "must be added" (`:135-148`) | Faltam comandos concretos e referência às composes | S |
| Kill switch em código | Ausente | só `scansolo_enabled` e `AiAgentConfig#enabled`; `scansolo_enabled` não para cadência nem proposta | Ver D-21 | M |

### Área 16 — Teste real controlado
| Requisito | Status | Evidência | Gap | Tam. |
|---|---|---|---|---|
| Exatamente uma resposta da IA etc. | Ausente | sem roteiro; depende de P0-1, 2, 5, 6 e 7 | Roteiro + critérios de aceite | S |

### Área 17 — Time Comercial
| Requisito | Status | Evidência | Gap | Tam. |
|---|---|---|---|---|
| Usuários, time e permissões | Ausente (dados) | Chatwoot nativo suporta; nada no repo | Lista de usuários e papéis (D-15) | S |
| SMTP | Desconhecido | só nomes no `.env.example` | D-16 | S |

### Área 18 — Observabilidade
| Requisito | Status | Evidência | Gap | Tam. |
|---|---|---|---|---|
| Turnos de IA e tokens | Implementado | `ai_turn.rb:3-30`, `ai_turns_controller.rb:9-26` | `latency_ms`/`cost_estimate` nunca escritos | S |
| Recuperação | Parcial | `context_snapshot['knowledge_context']` | Sem métricas agregadas | S |
| Tentativas de cadência | Implementado | `executions_controller.rb` | Motivo do skip ausente | S |
| Envio e falha de template, falhas de webhook Meta | Ausente (ScanSolo) | só `external_error` nativo | — | M |
| Callbacks Make, dead letters, retries | Parcial | executions | Dead letter inalcançável | — |
| Handoffs e erros recentes | Parcial | `AuditEvent` de takeover | Sem `ChatwootExceptionTracker` no ScanSolo | S |
| Nunca logar segredos | Implementado (excesso) | `scansolo_log_redaction.rb:16-27` | Apaga também UUIDs e correlation ids (`prompt_redactor.rb:16`) | S |

### Área 19 — Segurança
| Requisito | Status | Evidência | Gap | Tam. |
|---|---|---|---|---|
| Sem segredos no Git ou no frontend | Implementado | grep limpo; composes usam `${VAR}` | — | — |
| SSRF | Ausente (sem crawler) | — | Obrigatório quando houver fonte URL | — |
| Rate limiting | Parcial | só callback Make (`rack_attack.rb:345-353`) | knowledge create/reindex/retrieval/publish sem limite; `top_k` sem teto | S |
| Autorização por conta | Implementado | escopo `Current.account` nos controllers | — | — |
| Flag `scansolo_enabled` no front e no back | Parcial | back `base_controller.rb:5-11`; front só sidebar (`FE/index.js:13-15`) | Guard de rota | S |
| Papéis (admin) para publicar e alterar knowledge | Ausente | `ai_agent_config_policy.rb`, `knowledge_source_policy.rb` retornam `true` | — | S |
| Trilha de auditoria de admin | Parcial | só executor, takeover e return | publish, knowledge e flag | S |

### Área 20 — Testes
| Requisito | Status | Evidência | Gap | Tam. |
|---|---|---|---|---|
| model/service/request/job/frontend | Implementado (amplo) | 73 specs Ruby, 11 FE (ver CURRENT_STATE §3) | — | — |
| i18n, idempotência de cadência, handoff, RAG, disponibilidade de template, callback Make, dry-run de migração | Parcial | idempotência (`cadence_due_attempt_job_spec` "duplicate re-run"), guard (4), Make (12) | Faltam: completude i18n, prompt com RAG, callback→ProposalVersion, import LEXUS, humano sem takeover, rajada, Captain | M |
| E2E | Ausente | nenhum Playwright ScanSolo (`tests/playwright/` upstream) | — | M |

### Área 21 — UX geral dos 6 módulos
| Requisito | Status | Evidência | Gap | Tam. |
|---|---|---|---|---|
| Scroll | Quebrado | Área 1 | — | S |
| Loading, vazio, erro, sucesso | Parcial | vazio em FollowUps/Proposals/Executions; nenhum `uiFlags`/`useAlert` | — | M |
| Filtros e busca | Ausente | — | — | M |
| Confirmação destrutiva | Ausente | `KnowledgeCenter.vue:53-55`, `FollowUps.vue:82-89`, `Proposals.vue:119-127` | — | S |
| Labels pt-BR, tooltips | Parcial | Área 2 | — | S |
| Timestamps legíveis | Ausente | ISO cru (`KanbanBoard.vue:97,101`, `FollowUps.vue:53`, `OpportunityDetail.vue:83`) | — | S |
| Badges | Parcial | pills cinza; enums crus em `Executions.vue:43,61,105` | — | S |
| Sem IDs técnicos | Quebrado | `KanbanBoard.vue:93`, `KnowledgeCenter.vue:255-256`, `Executions.vue:95-98,165-170`, `TurnEvidenceViewer.vue:123-154` | Ver D-18 | S |

### Área 22 — Runbook de deploy
| Requisito | Status | Evidência | Gap | Tam. |
|---|---|---|---|---|
| Sem auto-deploy destrutivo; backup, build, migrations, restart, smoke, rollback; não mexer em domínio/Nginx/TLS | Parcial | `SCANSOLO_DEPLOYMENT.md:19-200` | Comando empilha dev; diz `chatwoot/chatwoot:latest` (`:23`); não carrega o seed de cadências; sem smoke test; profile Caddy conflitaria com o Nginx do host | M |

---

## 2. Priorização

### P0 — bloqueiam go-live (14)

Cada item foi verificado no código neste commit.

1. **Prompt sem contexto.** RAG, contato, pipeline e regras não chegam ao LLM (`turn_orchestrator.rb:154-157`).
2. **Nenhuma criação de `PipelineOpportunity`.** Pipeline, cadência, proposta e transição automática ficam inertes (`routes.rb:463`; grep).
3. **Propostas `MockProvider` em produção e Make não conectado.**
   - O envio real ao cliente leva um PDF falso e R$ 1500 (`mock_provider.rb:14-27`, `callback_handler.rb:55-66`).
   - `OutboundRequestService` não tem chamador.
   - O callback não aplica em `ProposalVersion` (`make_controller.rb:39-49`).
   - Mínimo aceitável para o go-live: desabilitar generate/send até existir integração real.
4. **Camada de ações inalcançável.** A IA não faz handoff, não captura qualificação nem opt-out (`conversation_listener.rb:17`, `turn_orchestrator.rb:18`; grep `Actions::Registry`).
5. **Turno preso em `pending`** sem registro de erro, e o retry é anulado pelo dedupe (`model_invoker.rb:16`, `turn_orchestrator.rb:47-56`).
6. **Humano responde e a IA não pausa; corrida takeover × LLM; rajadas geram N respostas** (`conversation_listener.rb:12`, `turn_orchestrator.rb:30-41`).
7. **Coexistência com Captain.** Se houver assistente Captain ativo num inbox da conta, os dois respondem (`hook_execution_service.rb:11-14`; nenhum guard em `app/services/scan_solo`). É condicional à D-17, mas o guard precisa existir ou a condição precisa ser garantida.
8. **`POSTGRES_PASSWORD=` vazio no compose de produção**, com drift em relação à VPS (`docker-compose.production.yaml:51`).
9. **Comando documentado mistura o compose de dev no de produção** (`SCANSOLO_DEPLOYMENT.md:40-41,110-111,134-135,148-149`; `docker-compose.scansolo.yaml:12-13`).
10. **Agent Center e demais telas sem scroll** (`Dashboard.vue:142-143`, `AgentCenter.vue:115`).
11. **Chaves i18n cruas** (10 campos) (`AgentCenter.vue:157,169,181`).
12. **Seed de `CadenceDefinition` não carregado em deploy.** Cadências e enroll pós-proposta são pulados em silêncio (`db/seeds.rb` sem referência; `success_handler.rb:36-37`).
13. **Cadências por estágio nunca começam.** Falta enroll automático, parada por resposta e checagem de handoff no job (`enrollment_service` chamadores; `ReplyCompletenessDetector` sem chamador; `cadence_due_attempt_job.rb:22-42`).
14. **Sem kill switch de outbound nem dono único vs LEXUS.** O risco é envio duplicado no cutover (grep; `PRODUCTION_CUTOVER.md:74-92` é só processo).

### P1 — necessários para operação completa (22)

1. Validação no publish, dropdowns de provider e modelo a partir de `llm.yml`, feedback de salvar/publicar, aviso de alterações não salvas, seções, ações sticky e `require_proposal_approval` na UI.
2. Usar `service_hours`, `response_limits`, `transfer_criteria`, `restricted_information` e `qualification_playbook` em runtime.
3. Policies admin-only para publish e knowledge, e `AuditEvent` para publish, knowledge e flag.
4. Templates:
   - parâmetros e idioma por tentativa;
   - motivo do skip gravado;
   - guard também para `scansolo_proposal_send`;
   - UI de templates.
5. Status Meta (delivered/failed) refletido em `CadenceAttempt` e `AiTurn`.
6. Pausa temporária de automação não deve consumir tentativas (`cadence_due_attempt_job.rb:35-38`).
7. Re-enroll após cancelamento: unique `(opportunity, definition)`.
8. Handoff:
   - pausar, encerrar e reabrir;
   - atribuição nativa;
   - `HandoffControlBanner` montado;
   - re-enroll no retorno à IA;
   - `proposal_status` real na nota.
9. Make:
   - `RetryPolicy` com rota e UI;
   - dead letter alcançável;
   - `failure_reason` na UI;
   - callback rejeitado não pode queimar o correlation id.
10. Confirmação de envio de proposta, de delete de knowledge e de cancelamento de follow-up.
11. Assinatura WhatsApp obrigatória também quando só existe o `WHATSAPP_APP_SECRET` global (`whatsapp_controller.rb:45-51`).
12. `Llm::Config` memoizado: definir o procedimento (restart) ou reinicializar quando a chave mudar.
13. Redação de log que preserve UUIDs e correlation ids (`prompt_redactor.rb:16`).
14. Ingestão assíncrona com status, erro e `indexed_at`; reingestão no update.
15. PDF e URL/crawl com SSRF (dependem de D-11, D-12 e D-13).
16. Estratégia de locale pt-BR (D-19) e teste de completude i18n.
17. Ferramenta de import LEXUS com dry-run e relatório (D-14).
18. Runbook:
    - `GIT_SHA` build arg;
    - corrigir o drift da doc;
    - smoke test;
    - rollback com comandos;
    - `.env.example` com `SCANSOLO_*`/`STORAGE_*`/`RATE_LIMIT_SCANSOLO_MAKE_CALLBACK`.
19. Rate limit nos endpoints ScanSolo autenticados e teto de `top_k`.
20. Observabilidade: `latency_ms`/`cost_estimate`, `ChatwootExceptionTracker` e falhas de template/webhook no painel.
21. Guard de rota `scansolo_enabled` no frontend e restrição de inbox para a IA (D-10).
22. Matriz de transições do pipeline (D-08) e tentativa inicial de Novo Lead (D-06).

### P2 — melhorias (10)

1. Índice HNSW/ivfflat em `scan_solo_knowledge_chunks.embedding`.
2. Fixar imagens e remover `version: '3'`.
3. Enumeração de contas via 404 × 401 (`base_controller.rb:5-11`).
4. Filtros, busca e paginação nas listas.
5. E2E Playwright para os 6 módulos.
6. Timestamps humanizados, badges coloridos, sem IDs técnicos (conforme D-18).
7. Remover `ScanSoloComingSoonPage.vue` e as strings `SCANSOLO.MODULES.*` mortas.
8. Toggle de `scansolo_enabled` no Super Admin.
9. `AgentBot` do remetente buscado por nome: renomear o config cria outro bot (`response_sender.rb:59-61`).
10. Utilitários Tailwind não lógicos (`TurnEvidenceViewer.vue:65` `text-left`) e `text-white` fixo (`AgentCenter.vue:232`).

---

## 3. Não reinventar

Infraestrutura existente que deve ser reutilizada, com a evidência verificada.

| Necessidade | Reutilizar | Evidência |
|---|---|---|
| WhatsApp envio e recebimento | Canal nativo `Channel::Whatsapp` (Cloud API), `Whatsapp::SendOnWhatsappService`, `IncomingMessage*Service`, `MessageDedupLock` | `app/services/whatsapp/*`; nunca criar cliente Graph paralelo |
| Janela de 24h | Enforcement nativo | `send_on_whatsapp_service.rb:15-17` |
| Status de entrega | `Messages::StatusUpdateService` + `external_error` | `incoming_message_base_service.rb:51-67` |
| Sync de templates | `WhatsappCloudService#sync_templates` + `TemplatesSyncSchedulerJob` | `whatsapp_cloud_service.rb:35-45`; `templates_sync_scheduler_job.rb:5-11` |
| Validação e envio de template | `Whatsapp::TemplateProcessorService` via `template_params` | `template_processor_service.rb:21-27` |
| Roteamento de modelo | `Llm::FeatureRouter` + `config/llm.yml` + `Llm::Config` (RubyLLM) | `lib/llm/feature_router.rb`, `lib/llm/config.rb` |
| Lista de providers e modelos para a UI | padrão `Llm::Models.providers/models` | `captain/preferences_controller.rb:19-22` |
| Fetch HTTP seguro (SSRF) | `SafeFetch` + gem `ssrf_filter` | `lib/safe_fetch.rb`, `lib/safe_fetch/private_network_request.rb`, `Gemfile:47` |
| HTML → texto | gem `reverse_markdown` | `Gemfile:197` |
| Crawl gerenciado (opcional) | gem `firecrawl-sdk` já no Gemfile | `Gemfile:215`. Uso atual é enterprise; decidir em D-12. Não usar `enterprise/app/services/page_crawler_service.rb` (licença e sem SSRF) |
| Vetores | `neighbor` + pgvector | `knowledge_chunk.rb:25-32` |
| Eventos | `AsyncDispatcher` + `BaseListener` | `async_dispatcher.rb:23` |
| Cron | sidekiq-cron em `config/schedule.yml` | `:79-84` |
| Atribuição e times | Chatwoot nativo (`Conversation#assignee`, teams, `AutoAssignment::AssignmentService`) | — |
| Layout com scroll | `SettingsWrapper.vue` / `components-next/captain/PageLayout.vue` | `SettingsWrapper.vue:22-24`, `PageLayout.vue:122,213` |
| Timestamps | helpers nativos `dynamicTime`/`messageStamp` | `app/javascript/shared/helpers/timeHelper.js:18,60` |
| Toasts | `useAlert` | `app/javascript/dashboard/composables/index.js` |
| Rate limiting | `rack_attack` | `config/initializers/rack_attack.rb` |
| Auditoria ScanSolo | `ScanSolo::AuditLogger.record!` | `audit_logger.rb:1-11` |
| Proposta idempotente | `CallbackHandler` (lock + correlation + `*_callback_applied_at`) | `callback_handler.rb:13-53`; ligar o callback Make a ele em vez de duplicar |
| Chamada Make | `ScanSolo::Make::OutboundRequestService` | `outbound_request_service.rb:35-86`; ligar, não reescrever |
| Parada e recálculo de cadência | `StopRecalculatePolicy`, `ReplyCompletenessDetector`, `LifecycleService` | já existem; falta ligar |
| Ações da IA | `ScanSolo::Actions::Registry/Executor/ConfirmationGate` | já existem; falta ligar ao turno |
