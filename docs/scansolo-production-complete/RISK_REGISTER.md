# ScanSolo Production Complete — Registro de Riscos

Gerado em 2026-09-23 a partir do commit 4af19b0bb (branch feat/scansolo-production-complete). Documento factual — não implementa nada.

Documentos relacionados: [CURRENT_STATE](CURRENT_STATE.md) · [ARCHITECTURE_MAP](ARCHITECTURE_MAP.md) · [GAP_ANALYSIS](GAP_ANALYSIS.md) · [DECISIONS_REQUIRED](DECISIONS_REQUIRED.md)

**Escalas:**
- **Probabilidade:** Alta / Média / Baixa, considerando o estado atual do código.
- **Impacto:** Crítico / Alto / Médio / Baixo.

**Gate:** o ponto do processo em que o risco precisa estar mitigado:
- **Go-live IA:** primeira resposta real da IA a um cliente.
- **Cutover:** desligar o LEXUS.
- **Deploy:** qualquer deploy na VPS.

As mitigações são direções, não implementações.

---

## Operacionais

| ID | Risco | Prob. | Impacto | Evidência | Mitigação | Dono / gate |
|---|---|---|---|---|---|---|
| RR-O1 | **Dupla resposta IA + humano.** Um agente responde no inbox sem clicar em takeover e a IA continua. Um takeover durante a chamada ao LLM não impede o envio. Rajadas geram N respostas. | Alta | Alto | `conversation_listener.rb:12` (só inbound); `turn_orchestrator.rb:30-41,114-121` (sem recheck); unique só por `message_id` | Takeover automático em saída humana ou atribuição (D-09); recheck de elegibilidade dentro da transação de envio; lock ou debounce por conversa | Dev / Go-live IA |
| RR-O2 | **LEXUS e Chatwoot operando juntos no mesmo número**: cadências e respostas duplicadas | Alta (no cutover) | Crítico | Nenhum kill switch (grep `kill.switch\|outbound_enabled` vazio); `scansolo_enabled` não para cadência nem proposta; `PRODUCTION_CUTOVER.md:74-92` só processo | Flag única de outbound (D-21); checklist de dono único com verificação do webhook Meta; rollback com comandos | Produto+Ops / Cutover |
| RR-O3 | **Proposta falsa enviada ao cliente**: R$ 1500 e URL `mock-proposals.scansolo.test`, e o estágio vai para proposta_enviada | Média (exige clique de usuário) | Crítico | `generate_service.rb:12`, `send_service.rb:10`, `mock_provider.rb:14-27`, `callback_handler.rb:55-66`, `proposals_controller.rb:25,45-48` | Desabilitar generate/send em produção até a integração Make (D-04); confirmação no envio | Dev / Go-live IA |
| RR-O4 | **Explosão de custo em embeddings e LLM** | Média | Alto | Ingestão síncrona com 1 chamada por chunk de ~500 caracteres (`ingestion_service.rb:24-27`); sem throttle (`rack_attack.rb:346-349`); `top_k` sem teto (`retrieval_tests_controller.rb:25-27`); uma resposta por mensagem de rajada; `cost_estimate` nunca escrito | Rate limit por conta; teto de `top_k`; job assíncrono; gravar custo; orçamento (D-23) | Dev+Produto / Go-live IA |
| RR-O5 | **Turno preso em `pending`**: cliente sem resposta, sem registro de falha e sem alerta | Média | Alto | `model_invoker.rb:16` (só `PROVIDER_ERRORS`); `retrieval_service.rb:13` (só `OUTAGE_ERRORS`); retry colide com o índice único (`turn_orchestrator.rb:47-56`); mensagem só com anexo gera query vazia (`context_assembler.rb:84`) | Marcar `failed` em qualquer exceção e reportar ao `ChatwootExceptionTracker`; tratar mensagem sem texto; job de varredura de `pending` antigo | Dev / Go-live IA |
| RR-O6 | **Redação de log apaga correlation ids e UUIDs**, o que impede rastrear incidentes | Alta | Médio | `prompt_redactor.rb:16` (`\b[A-Za-z0-9_\-]{32,}\b`), aplicado a toda linha de log (`scansolo_log_redaction.rb:16-27`); `correlation_id = SecureRandom.uuid` (`turn_orchestrator.rb:51`) | Regex que não case com UUID nem hex de request id; teste cobrindo UUID | Dev / Go-live IA |
| RR-O7 | **Cache do `Llm::Config` exige restart**: chave salva ou rotacionada após o boot não é usada, e todo turno falha com `ConfigurationError` | Média (a chave foi salva em produção, reportado pelo usuário) | Alto | `lib/llm/config.rb:11-16` memoiza `@initialized` mesmo sem chave; nenhuma chamada a `reset!` no app | Reiniciar rails e sidekiq após alterar a chave (runbook); smoke test de um turno | Ops / Deploy |
| RR-O8 | **A IA responde sem base de conhecimento**: alucinação sobre serviços e condições da ScanSolo | Alta | Alto | `turn_orchestrator.rb:154-157` (só histórico); `restricted_information`/`service_hours`/`transfer_criteria` não usados | Incluir o contexto recuperado e as regras no prompt; spec de que o prompt contém knowledge | Dev / Go-live IA |
| RR-O9 | **Captain e ScanSolo respondem à mesma mensagem** | Baixa–Média (depende de D-17) | Alto | `hook_execution_service.rb:11-14`; nenhum `captain_active` em `app/services/scan_solo` | Guard de coexistência ou Captain desativado na conta (D-17) | Produto+Dev / Go-live IA |
| RR-O10 | **Evidência de cadência falsa**: attempt "sent" rejeitado pela Meta; template com variável falha | Alta (se o template tiver variáveis) | Médio | `cadence_due_attempt_job.rb:46-50`; `attempt_evidence_recorder.rb:11-13` (ignora a mensagem); `native_template_sender.rb:52,54` | Guardar `message_id` no attempt e refletir o status Meta; passar parâmetros e idioma por mapeamento (D-03) | Dev / Cutover |
| RR-O11 | **Pausa de automação ou indisponibilidade de template consome as tentativas para sempre** | Média | Médio | `cadence_due_attempt_job.rb:35-38` (`skipped` terminal) | Adiar em vez de pular quando o motivo for temporário; gravar o motivo | Dev / Cutover |
| RR-O12 | **Cadências não existem em produção** porque o seed não é carregado; o enroll pós-proposta é pulado em silêncio | Alta | Alto | `db/seeds.rb` sem referência a `scansolo_cadence_definitions`; `success_handler.rb:36-37` retorna em silêncio; runbook não menciona o seed | Passo explícito no runbook ou migration de dados; check no smoke test | Ops+Dev / Deploy |
| RR-O13 | **Cadência continua depois de handoff, resolução ou resposta do lead** | Média | Médio | `cadence_due_attempt_job.rb:22-42` não checa `ai_control_state`, status da conversa ou flag; `ReplyCompletenessDetector` sem chamador | Pré-checagens no job; ligar a parada por resposta | Dev / Cutover |
| RR-O14 | **Resposta da IA fora da janela de 24h falha no WhatsApp**, mas o turno fica `succeeded` | Média | Baixo | `send_on_whatsapp_service.rb:15-17`; `response_sender.rb:47-57` | Refletir o status da mensagem no turno ou no painel | Dev / Go-live IA |
| RR-O15 | **A IA responde em inbox indesejada** (e-mail, outros canais da conta) | Média | Médio | Nenhum filtro por inbox (`conversation_listener.rb:10-18`) | Allowlist de inboxes (D-10) | Produto+Dev / Go-live IA |

## Segurança

| ID | Risco | Prob. | Impacto | Evidência | Mitigação | Dono / gate |
|---|---|---|---|---|---|---|
| RR-S1 | **Webhook WhatsApp sem app secret no canal pula a validação de assinatura** mesmo com o `WHATSAPP_APP_SECRET` global, o que permite injetar mensagens forjadas | Média | Alto | `whatsapp_controller.rb:45-51` | Gravar o App Secret no canal (D-02); exigir assinatura quando houver secret global | Admin Meta+Ops / Go-live IA |
| RR-S2 | **Um agente não-admin publica o config do agente ou altera e apaga a base**, sem trilha de auditoria | Média | Alto | `ai_agent_config_policy.rb` e `knowledge_source_policy.rb` retornam `true`; `AuditLogger.record!` só em executor, takeover e return | Policies admin-only (D-15); `AuditEvent` em publish e knowledge | Dev / Go-live IA |
| RR-S3 | **SSRF ao adicionar fonte URL/crawl** sem controles | Alta (se o crawler for feito sem SafeFetch) | Alto | Não há crawler; `enterprise/app/services/page_crawler_service.rb:6` usa `HTTParty.get` sem proteção | Usar `lib/safe_fetch.rb` + `ssrf_filter`; allowlist de domínio (D-11/D-12) | Dev / antes do crawler |
| RR-S4 | **Sem rate limit em endpoints ScanSolo autenticados**, o que abre abuso de API paga e DoS | Média | Médio | `rack_attack.rb:345-353` (só o callback Make) | Throttle por conta e usuário em knowledge, reindex, retrieval_tests e publish | Dev / Go-live IA |
| RR-S5 | **Enumeração de contas ScanSolo**: 404 (desabilitada) × 401/403 (habilitada) antes da autenticação | Baixa | Baixo | `base_controller.rb:5-11` | Aceitar o risco ou aplicar o guard depois da autenticação | Dev / P2 |
| RR-S6 | **Rotas do frontend acessíveis por URL** com a flag desligada; o shell carrega, sem dados | Baixa | Baixo | `FE/index.js:13-15` | Guard de rota com `scansolo_enabled` | Dev / P1 |
| RR-S7 | **Segredos Make em Rails credentials** exigem gestão da master key na VPS | Média | Médio | `outbound_request_service.rb` (credentials `scan_solo.make.*`); `callback_verifier.rb:90-96` | Procedimento de provisionamento no runbook; nunca versionar a master key | Ops / antes da integração Make |

## Deploy

| ID | Risco | Prob. | Impacto | Evidência | Mitigação | Dono / gate |
|---|---|---|---|---|---|---|
| RR-D1 | **Drift entre o compose no Git e a VPS**: um próximo deploy a partir do Git reintroduz a senha vazia do Postgres | Alta | Crítico | `docker-compose.production.yaml:51`; correção manual na VPS (reportado pelo usuário) | `POSTGRES_PASSWORD=${POSTGRES_PASSWORD}` no Git (D-20); `diff` do compose da VPS com o Git antes de todo deploy | Ops / Deploy |
| RR-D2 | **O compose de dev mesclado ao de produção** expõe 5432, 6379 e 3000 publicamente, monta `./:/app` sobre a imagem e sobe vite e mailhog | Alta (se o doc for seguido) | Crítico | `SCANSOLO_DEPLOYMENT.md:40-41,110-111,134-135,148-149`; `docker-compose.yaml:25,37,89,105,64-77,107-111` | Corrigir o comando oficial; lint da combinação real de produção em spec | Ops+Dev / Deploy |
| RR-D3 | **Imagens não fixadas** geram builds e runtimes diferentes entre deploys | Média | Médio | `redis:alpine`, `pgvector/pgvector:pg16`, `node:24-alpine` (`Dockerfile:2`), `minio/minio:latest`, `caddy:2-alpine`, `postgres:16-alpine`; `apk add` sem versão | Fixar tag ou digest | Ops / Deploy |
| RR-D4 | **O build falha sem `.git` real** (worktree, tarball, CI) | Média | Médio | `Dockerfile:90` `git rev-parse HEAD`; `.git` fora do `.dockerignore` | `ARG GIT_SHA` → `/app/.git_sha` (D-20) | Dev / Deploy |
| RR-D5 | **Ativar o profile `reverse-proxy` (Caddy 80/443)** conflita com o Nginx/TLS do host e pode derrubar o domínio | Baixa | Alto | `docker-compose.scansolo.yaml:90-111`; Nginx no host (reportado pelo usuário) | Runbook: nunca ativar `reverse-proxy`; não mexer em Nginx/TLS | Ops / Deploy |
| RR-D6 | **Documentação de deploy desatualizada** leva a erro operacional | Alta | Médio | `SCANSOLO_DEPLOYMENT.md:23` (`chatwoot/chatwoot:latest`), `:157-161` (`STORAGE_*` "documentado" e ausente do `.env.example`) | Atualizar o doc e o `.env.example` (só nomes) | Dev / Deploy |
| RR-D7 | **Migrations sem backup prévio garantido** ou `base` subindo junto no `up` | Baixa | Alto | Profile `backup` manual (`docker-compose.scansolo.yaml:117-130`); serviço `base` sem comando (`docker-compose.production.yaml:4-11`) | Runbook: backup → build → migrate → restart → smoke → rollback | Ops / Deploy |

## Dados

| ID | Risco | Prob. | Impacto | Evidência | Mitigação | Dono / gate |
|---|---|---|---|---|---|---|
| RR-DA1 | **Constraint única impede re-enroll** depois de cancelar, voltar de estágio ou re-inscrever após migração | Alta | Médio | unique `(opportunity_id, cadence_definition_id)` (`db/migrate/20260918060001_*:20-21`); `enrollment_service.rb:18-25` devolve o existente | Unique parcial só para enrollments ativos, ou nova versão de definição | Dev / Cutover |
| RR-DA2 | **Callback Make rejeitado consome o correlation id**: um callback válido posterior recebe 200 e nunca é aplicado | Média | Alto | `make_controller.rb:16,35-37,51-59`; unique permanente `make_callbacks.correlation_id` (`db/migrate/20260918080001_*:21`) | `already_processed?` considerar só `applied: true`; guardar rejeições sem ocupar a chave única | Dev / antes da integração Make |
| RR-DA3 | **Fonte de conhecimento salva com 0 chunks** quando o embedding falha, e o admin não é avisado | Média | Médio | `ingestion_service.rb:19` (save antes do embed); sem status nem erro no jbuilder | Status e erro de indexação; ingestão em job | Dev / Go-live IA |
| RR-DA4 | **PDF anexado nunca é indexado**: o admin acredita que está na base | Alta (se houver upload) | Médio | `ingestion_service.rb:20`; sem validação de tipo ou tamanho (`knowledge_source.rb:36-40`) | Bloquear upload ou implementar o parse (D-13) | Dev / Go-live IA |
| RR-DA5 | **Import LEXUS duplica contatos e conversas** (quando existir) | Média | Alto | Não há código; dedupe indefinido (`SCANSOLO_LEXUS_CUTOVER_DESIGN.md:306-314`) | Dry-run com relatório; chave de dedupe (D-14) | Dev / Cutover |
| RR-DA6 | **`AgentBot` duplicado** ao renomear o agente, com histórico fragmentado por remetente | Média | Baixo | `response_sender.rb:59-61` (`find_or_create_by!` por nome) | Referenciar o bot por id | Dev / P2 |
| RR-DA7 | **Mudanças de knowledge sem reindex** ficam com chunks obsoletos | Alta | Médio | `sources_controller.rb:26-30` (update sem reingestão) | Reingerir quando `content` mudar | Dev / Go-live IA |
