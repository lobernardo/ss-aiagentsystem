# Phases: scansolo-relatorios-fonte-unica

Gerado por /plan a partir de PLAN.md — view executável para `./ralph.sh .spec/features/scansolo-relatorios-fonte-unica/PHASES.md`.

Regras de todas as fases: migrações só aditivas; specs com `scan_solo`/`scansolo` no caminho; i18n só em `app/javascript/dashboard/i18n/locale/en/scansolo.json` (pt-BR) e `config/locales/en.yml`; nome público "Artur", nunca "Luciano"; nenhum telefone no Git; Vue `<script setup>` + Tailwind + `components-next/`; sem commit/push/deploy; `./scripts/ralph-test.sh` verde ao fim da fase.

## Phase 1: Fundações (schema, período, regra de parado)

Antes de implementar, leia:
1. `.spec/features/scansolo-relatorios-fonte-unica/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-relatorios-fonte-unica/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T01 — Migrações aditivas e modelos (handled_manually + report snapshots)
      Arquivos: `db/migrate/<ts>_add_handled_manually_to_scan_solo_quote_requests.rb`, `db/migrate/<ts>_create_scan_solo_report_snapshots.rb`, `db/schema.rb`, `app/models/scan_solo/quote_request.rb`, `app/models/scan_solo/report_snapshot.rb`
      Mudança: adicionar `handled_manually_at` (datetime) e `handled_manually_by_id` (FK users, null) em `scan_solo_quote_requests`; criar `scan_solo_report_snapshots` (`account_id` FK not null, `week_start date`, `payload jsonb`, `generated_at`, timestamps, índice único `(account_id, week_start)`); enum `handled_manually: 3` sem renumerar 0..2; `belongs_to :handled_manually_by` opcional; modelo `ScanSolo::ReportSnapshot`. Sem `remove_*`/`rename_*`/`change_column`.
      Cobre: CT-05, RF-13, RF-16, RNF-04
      Acceptance criteria: `ScanSolo::QuoteRequest.statuses` = `{awaiting_reply: 0, correction_requested: 1, replied: 2, handled_manually: 3}`; `db/schema.rb` tem as 2 colunas novas e a tabela com índice único `(account_id, week_start)`; as migrações não contêm `remove_`, `rename_` nem `change_column`; `open?` é false para `handled_manually`.
      Testes: `spec/models/scan_solo/report_snapshot_spec.rb` — unicidade (conta, week_start); `spec/models/scan_solo/quote_request_spec.rb` — valores do enum e `open?`
- [ ] T02 — `ScanSolo::Reports::Period` (resolução de período em America/Sao_Paulo)
      Arquivos: `app/services/scan_solo/reports/period.rb`
      Mudança: objeto puro `Period.resolve(period:, anchor:)` com `starts_at`, `ends_at` exclusivo, `previous` do mesmo tipo e `closed?(now)`, calculados em `America/Sao_Paulo` (semana começa na segunda); constantes `TIMEZONE` e `PERIODS = %w[week month]`.
      Cobre: RF-07, RF-09, RNF-07
      Acceptance criteria: `anchor=2026-11-08`, `week` → `2026-11-02T00:00:00-03:00` até `2026-11-09T00:00:00-03:00` (exclusivo); `2026-11-09T02:59:59Z` está no intervalo e `03:00:00Z` não; o período anterior de week/month é o imediatamente anterior; o spec passa com o servidor em UTC.
      Testes: `spec/services/scan_solo/reports/period_spec.rb` — fronteiras de semana e mês, período anterior
- [ ] T03 — Regra única de "parado" no backend (`OpportunityQuery`)
      Arquivos: `app/services/scan_solo/pipeline/opportunity_query.rb`
      Mudança: `stale?(opportunity, now:)` = etapa ∉ {ganho, perdido} e `COALESCE(last_customer_interaction_at, created_at) <= now - PIPELINE_STALE_THRESHOLD`; novo `stalled_scope(scope, as_of:)` com o mesmo `COALESCE` em SQL; `filter_by_stale` reutiliza `stalled_scope`.
      Cobre: RF-04, RF-10
      Acceptance criteria: interação há 47h59 → false, 48h00 → true; interação nula e `created_at` há 48h00 → true, 47h59 → false; `ganho`/`perdido` há 30 dias → false; `stalled_scope` devolve o mesmo conjunto que `stale?` nos mesmos casos; não há segunda cópia do `COALESCE` no arquivo.
      Testes: `spec/services/scan_solo/pipeline/opportunity_query_spec.rb` — casos (a)–(c) do RF-04 e equivalência `stale?`/`stalled_scope`

## Phase 2: Classificador comercial e indicadores

Antes de implementar, leia:
1. `.spec/features/scansolo-relatorios-fonte-unica/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-relatorios-fonte-unica/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-relatorios-fonte-unica/openapi.yaml` — forma de `summary` (CT-01) e enum `CommercialStatus`

- [ ] T04 — `ScanSolo::Reports::CommercialStatus` (classificador puro)
      Arquivos: `app/services/scan_solo/reports/commercial_status.rb`
      Mudança: `CommercialStatus.call(quote_request:, current_version:)` com a tabela do RF-01 na ordem exata; `VALUES` (6); `forwarded_at(quote_request)` → `sent_at` ou nil. Único arquivo Ruby com essa tabela; sem I/O.
      Cobre: RF-01, RF-02, RF-03, RNF-03
      Acceptance criteria: as 6 linhas do RF-01 devolvem o valor da tabela; `replied` + versão `generating`/`approved`/`failed` → `resposta_recebida`; `awaiting_reply` + versão `rejected` → `aguardando_artur`; nenhum `escalado_wa`; 0 `INSERT/UPDATE/DELETE` durante as chamadas.
      Testes: `spec/services/scan_solo/reports/commercial_status_spec.rb` — 6 linhas + 2 bordas + assert de 0 escritas
- [ ] T05 — `ScanSolo::Reports::PeriodSummary` (indicadores SQL só leitura)
      Arquivos: `app/services/scan_solo/reports/period_summary.rb`
      Mudança: `PeriodSummary.call(account:, range:)` devolve o `summary` do CT-01 com chaves completas (zeros nos grupos vazios): leads novos por origem, respondidos (coorte do período, 1ª incoming não privada → outgoing não privada posterior), mediana/p90 em minutos (`percentile_cont`, null se vazio), turnos de IA por status e motivo normalizado, inbound sem turno, cadências por resultado e por bloqueio, qualificados (eventos `to_stage='qualificado'` ∪ audit de lead manual em `qualificado`, distintos), encaminhados (`sent_at`), propostas por status. Só SELECT, sem conteúdo de mensagem.
      Cobre: RF-08, RF-09, RNF-01, RNF-03
      Acceptance criteria: cada indicador é igual à SQL de referência do RF-08 executada no mesmo banco de teste; lead respondido só por cadência conta em `responded`; lead manual sem incoming fica fora de `responded` e da amostra; lead da semana anterior respondido nesta semana fica fora; lead manual criado em `qualificado` conta em `qualified`; 2 eventos `to_stage='qualificado'` contam 1; fronteira de domingo 23:59:59 SP respeitada; 0 escritas.
      Testes: `spec/services/scan_solo/reports/period_summary_spec.rb` — 1 exemplo por indicador conferido contra a SQL de referência + casos obrigatórios do RF-08

## Phase 3: Motivo de parada e JSON da oportunidade

Antes de implementar, leia:
1. `.spec/features/scansolo-relatorios-fonte-unica/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-relatorios-fonte-unica/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-relatorios-fonte-unica/openapi.yaml` — `PipelineOpportunity` (CT-02), `StallReason`, `SuggestedAction`

- [ ] T06 — `ScanSolo::Reports::StallReason` + tabela motivo → ação sugerida
      Arquivos: `app/services/scan_solo/reports/stall_reason.rb`
      Mudança: `StallReason.call(opportunity:, now:, commercial_status:, legacy_bulk:)` puro sobre associações pré-carregadas; "inscrição da etapa atual" = enrollment mais recente cuja `cadence_definition.stage` = etapa atual (filtrado em Ruby); 10 motivos na precedência do RF-05; motivo 5 só com `commercial_status == 'proposta_enviada_manual'` e `legacy_bulk`; etapas com cadência de `Cadence::StageEntryEnroller::STAGES`; `REASONS` (10) e `SUGGESTED_ACTIONS` (10, `SCANSOLO.REPORTS.SUGGESTED_ACTIONS.<REASON>`).
      Cobre: RF-05, RF-06, RNF-03
      Acceptance criteria: 1 caso por motivo (10) devolve o motivo esperado; humano + bloqueio → `em_atendimento_humano`; legado do lote (inscrição `cancelled`, `legacy_bulk: true`) → `proposta_manual_sem_cadencia`, nunca `sem_followup_agendado`; unitária (`legacy_bulk: false`, inscrição `completed`) → `cadencia_concluida_sem_resposta`; `SUGGESTED_ACTIONS` tem 10 entradas; 0 consultas SQL durante `call` com dados pré-carregados.
      Testes: `spec/services/scan_solo/reports/stall_reason_spec.rb` — 10 casos + 3 de precedência + contagem de consultas
- [ ] T07 — CT-02: `commercial_status` e `commercial_forwarded_at` no JSON da oportunidade
      Arquivos: `app/views/api/v1/accounts/scan_solo/pipeline_opportunities/_pipeline_opportunity.json.jbuilder`
      Mudança: acrescentar `commercial_status` (via `CommercialStatus.call` com `quote_request` e `proposal&.current_version` pré-carregados) e `commercial_forwarded_at` (via `CommercialStatus.forwarded_at`); `quote_request_status` e `proposal_status` permanecem.
      Cobre: CT-02, RF-02, RF-03, RNF-02
      Acceptance criteria: index e show devolvem `commercial_status` igual ao do classificador para a mesma oportunidade; `commercial_forwarded_at` = `sent_at` em ISO 8601 ou `null` sem pedido; a contagem de consultas do index é a mesma com 2 e com 6 oportunidades com pedido/proposta.
      Testes: `spec/requests/api/v1/accounts/scan_solo/pipeline_opportunities_spec.rb` — campos novos em index/show + contagem de consultas

## Phase 4: Montagem do relatório

Antes de implementar, leia:
1. `.spec/features/scansolo-relatorios-fonte-unica/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-relatorios-fonte-unica/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-relatorios-fonte-unica/openapi.yaml` — schema `Report` (CT-01)

- [ ] T08 — `ScanSolo::Reports::ReportBuilder` (corpo CT-01: resumo, anterior, funil, parados)
      Arquivos: `app/services/scan_solo/reports/report_builder.rb`
      Mudança: `ReportBuilder.call(account:, period:, now:, source:)` → Hash com as chaves do CT-01; `summary` e `previous.summary` por `PeriodSummary`; funil 8 etapas na ordem do enum com `active`/`stalled` via `OpportunityQuery.stalled_scope(as_of: now)`; lista de parados com preload (`contact`, `quote_request`, `conversation_extension`, `proposal: :current_version`, `cadence_enrollments: [:cadence_definition, :attempts]`) e 1 única consulta de audit `quote_request.handled_manually` com `payload->>'cadence_skipped' = 'legacy_bulk'` → `legacy_bulk:` do `StallReason`; item com `opportunity_id`, `contact_name`, `stage`, `last_customer_interaction_at`, `created_at`, `commercial_status`, `stall_reason`, `suggested_action`. Só leitura, sem telefone/e-mail/conteúdo.
      Cobre: RF-09, RF-10, RF-14, RNF-01, RNF-02, RNF-03
      Acceptance criteria: funil igual à SQL de referência do RF-10 (`ganho`/`perdido` com `stalled = 0`); soma de `stalled` = tamanho da lista; cada parado aparece 1 vez com o `stall_reason` do classificador; lead legado do lote em `proposta_enviada` aparece com `proposta_manual_sem_cadencia`; 3 leads em W e 5 em W−1 → `new_leads.total` 3 e `previous...new_leads.total` 5; mesma contagem de consultas com 3 e 30 parados; 0 escritas; JSON sem `@`, `+55` nem conteúdo de mensagem de fixture.
      Testes: `spec/services/scan_solo/reports/report_builder_spec.rb` — funil, lista, anterior, contagem 3×30, privacidade, 0 escritas

## Phase 5: API de relatório e snapshot semanal

Antes de implementar, leia:
1. `.spec/features/scansolo-relatorios-fonte-unica/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-relatorios-fonte-unica/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-relatorios-fonte-unica/openapi.yaml` — `GET /accounts/{account_id}/scan_solo/reports` (CT-01)

- [ ] T09 — CT-01: `ReportsController#index` + `ReportPolicy` + rota
      Arquivos: `app/controllers/api/v1/accounts/scan_solo/reports_controller.rb`, `app/policies/scan_solo/report_policy.rb`, `config/routes.rb`
      Mudança: `get 'reports', to: 'reports#index'` no `namespace :scan_solo`; controller herda `ScanSolo::BaseController`, `ReportPolicy#index? → true`; valida `period` (→ 422 `invalid_period`) e `anchor` `YYYY-MM-DD` real (→ 422 `invalid_anchor`), anchor padrão = hoje em SP; semana fechada com snapshot → `render json: snapshot.payload`; senão `ReportBuilder` com `source: 'live'`; nunca grava.
      Cobre: RF-11, RF-12, RF-14, CT-01, RNF-01, RNF-02
      Acceptance criteria: conta desabilitada 404; sem token 401; administrador 200; agente 200; `period=day` → 422 `invalid_period`; `anchor=2026-02-30` → 422 `invalid_anchor`; sem anchor → período da data atual em SP; semana passada com snapshot → `source = "snapshot"` e corpo = `payload`; semana corrente → `live`; semana passada sem snapshot → `live` e 0 linhas criadas; contagem de linhas das tabelas `scan_solo_*` igual antes/depois; contagem de consultas igual com 3 e 30 parados; corpo sem `@`/`+55`/conteúdo.
      Testes: `spec/requests/api/v1/accounts/scan_solo/reports_spec.rb` — permissões, 422, snapshot/live, 0 escritas, consultas, privacidade
- [ ] T10 — Snapshot semanal: `WeeklyReportSnapshotJob` + `schedule.yml`
      Arquivos: `app/jobs/scan_solo/weekly_report_snapshot_job.rb`, `config/schedule.yml`
      Mudança: job `scheduled_jobs`; `week_start` = segunda da semana anterior em SP; para cada conta com `scansolo_enabled`, `ReportBuilder` (`period: week`, `source: 'snapshot'`) e `ReportSnapshot.upsert(..., unique_by: %i[account_id week_start])` sobrescrevendo `payload`, `generated_at`, `updated_at`; entrada `scan_solo_weekly_report_snapshot_job` com `cron: '0 9 * * 1'` e `queue: scheduled_jobs`. Confirmar o escopo `Account.scansolo_enabled` do flag_shih_tzu (PLAN A-03).
      Cobre: RF-13, CT-05, CT-06, RNF-01, RNF-07
      Acceptance criteria: rodar em `2026-11-09T06:00-03:00` grava `week_start = 2026-11-02`; 2 execuções → exatamente 1 linha com `payload`/`generated_at` da 2ª; conta com `scansolo_enabled = false` não ganha linha; payload com `source = "snapshot"` e sem `@`/`+55`/conteúdo; `config/schedule.yml` tem a entrada com cron `'0 9 * * 1'`.
      Testes: `spec/jobs/scan_solo/weekly_report_snapshot_job_spec.rb` — semana anterior, idempotência, conta desabilitada, privacidade, entrada do schedule

## Phase 6: Ação manual (service) e guarda RF-19

Antes de implementar, leia:
1. `.spec/features/scansolo-relatorios-fonte-unica/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-relatorios-fonte-unica/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T11 — `ScanSolo::Quote::HandledManuallyService` (ação manual unitária/lote)
      Arquivos: `app/services/scan_solo/quote/handled_manually_service.rb`, `lib/custom_exceptions/scan_solo.rb`
      Mudança: `call(opportunity:, actor:, mode:)`; sem pedido → `quote_request_missing`; sob `quote_request.with_lock`: não `open?` → `quote_request_closed`; etapa ∉ {qualificado, proposta_enviada} → `invalid_stage`; na mesma transação: `StageTransitionService` para `proposta_enviada` com o ator (se ainda não estiver), `status: handled_manually` + at/by, em `bulk` `LifecycleService.cancel!` em toda inscrição `active`/`paused` com definição `stage = proposta_enviada`, audit `quote_request.handled_manually` (payload CT-07, `cadence_skipped: 'legacy_bulk'` em bulk). Nova `CustomExceptions::ScanSolo::HandledManuallyRejected` com `code`. Nenhuma mensagem, e-mail, Make ou versão de proposta.
      Cobre: RF-15, RF-16, RF-17, RF-20, CT-07
      Acceptance criteria: os 3 códigos não alteram nenhuma linha; aceito em `qualificado` → 1 `PipelineStageEvent` `qualificado → proposta_enviada` com o usuário, pedido `handled_manually` com at/by, 1 audit; já em `proposta_enviada` → 0 eventos; `Message`, `MakeRequest`, `ProposalVersion` e jobs de e-mail inalterados nos 2 modos; single → inscrição de `proposta_enviada` `active` com tentativas `scheduled` futuras; bulk com transição → inscrição `cancelled`, 0 `scheduled`, `cadence_skipped = legacy_bulk`; bulk sem transição (1 `active` + 1 `paused`) → ambas `cancelled`; falha no cancelamento → nada persistido; 2 ações concorrentes → 1 sucesso + 1 `quote_request_closed`, 1 audit, ≤ 1 evento.
      Testes: `spec/services/scan_solo/quote/handled_manually_service_spec.rb` — elegibilidade, efeitos, cadência por modo, rollback, concorrência
- [ ] T12 — RF-19: `ReplyProcessor` e `ResendService` tratam `handled_manually` como fechado
      Arquivos: `app/services/scan_solo/quote/reply_processor.rb`, `app/services/scan_solo/quote/resend_service.rb`
      Mudança: em `ReplyProcessor.apply`, sob o lock, pedido `handled_manually` → `:late_reply` (sem mudar status nem pedir geração); em `ResendService#reusable_request`, `handled_manually` também → `quote_request_closed`.
      Cobre: RF-19
      Acceptance criteria: e-mail com bloco CT-04 válido na thread de pedido `handled_manually` cria 1 `QuoteReply` `late_reply` `pending`, o pedido continua `handled_manually` e 0 `ProposalVersion` são criadas; `POST .../quote_request/resend` de pedido `handled_manually` → 422 `quote_request_closed`; comportamento de `replied`/`awaiting_reply`/`correction_requested` inalterado.
      Testes: `spec/services/scan_solo/quote/reply_processor_spec.rb` — late_reply para `handled_manually`; `spec/requests/api/v1/accounts/scan_solo/quote_request_resend_spec.rb` — 422 `quote_request_closed`

## Phase 7: Endpoints da ação manual

Antes de implementar, leia:
1. `.spec/features/scansolo-relatorios-fonte-unica/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-relatorios-fonte-unica/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-relatorios-fonte-unica/openapi.yaml` — CT-03 e CT-04

- [ ] T13 — CT-03 e CT-04: endpoints da ação manual + policies + rotas
      Arquivos: `app/controllers/api/v1/accounts/scan_solo/pipeline_opportunities_controller.rb`, `app/controllers/api/v1/accounts/scan_solo/quote_requests_controller.rb`, `app/policies/scan_solo/pipeline_opportunity_policy.rb`, `app/policies/scan_solo/quote_request_policy.rb`, `config/routes.rb`
      Mudança: rota membro `post 'quote_request/handled_manually', to: 'pipeline_opportunities#handled_manually'` (reusa `set_opportunity`, `project_lead_state`, `render :show`; mode `single`; 422 `{ error: code }`); rota `post 'quote_requests/handled_manually', to: 'quote_requests#bulk_handled_manually'` (valida `opportunity_ids` array não vazio de inteiros → senão 422 `invalid_opportunity_ids`; por id: fora da conta → `not_found`, senão service mode `bulk` → `handled` ou código; 200 `{ results }`); policies `handled_manually?` e `bulk_handled_manually?` → `account_user.present?`.
      Cobre: CT-03, CT-04, RF-15, RF-16, RF-18, RF-20
      Acceptance criteria: CT-03 aceito (agente e admin) → 200 com `commercial_status = "proposta_enviada_manual"`; `quote_request_missing`, `quote_request_closed`, `invalid_stage` → 422 sem alterar linhas; oportunidade de outra conta → 404; conta desabilitada → 404; sem token → 401; CT-04 com (elegível, já `handled_manually`, outra conta) → 200 com `handled`, `quote_request_closed`, `not_found` e só o elegível muda, terminando sem inscrição pós-proposta `active`/`paused`; `[]`, ausente ou `["x"]` → 422 `invalid_opportunity_ids`; rubocop sem ofensas.
      Testes: `spec/requests/api/v1/accounts/scan_solo/quote_request_handled_manually_spec.rb` — CT-03 e CT-04 com permissões e códigos

## Phase 8: Base do frontend (i18n, APIs, stores)

Antes de implementar, leia:
1. `.spec/features/scansolo-relatorios-fonte-unica/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-relatorios-fonte-unica/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-relatorios-fonte-unica/openapi.yaml` — CT-01, CT-03, CT-04 (consumo)

- [ ] T14 — Frontend: mapas de rótulo e i18n pt-BR
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/scansoloLabels.js`, `app/javascript/dashboard/i18n/locale/en/scansolo.json`, `app/javascript/dashboard/routes/dashboard/scansolo/specs/i18nCompleteness.spec.js`
      Mudança: `COMMERCIAL_STATUS_LABELS` (6), `STALL_REASON_LABELS` (10), `SUGGESTED_ACTION_LABELS` (10, chaves iguais às do backend), `HANDLED_MANUALLY_ERROR_LABELS`; `handled_manually` em `QUOTE_REQUEST_COMMERCIAL_STATUS_LABELS`; em `scansolo.json` todas as chaves novas (`SIDEBAR.REPORTS`, `MODULES.REPORTS.*`, situações, motivos, ações, tela Relatórios, filtro, botão/diálogos unitário e em lote, "Encaminhado ao Artur em {date}", erros); os 3 mapas no `enumKeys` do i18nCompleteness.
      Cobre: UI-11, RF-06, RNF-05
      Acceptance criteria: `i18nCompleteness.spec.js` passa com os 3 mapas (6/10/10) no `enumKeys` e com `SIDEBAR.REPORTS`, `MODULES.REPORTS.TITLE/DESCRIPTION` presentes; `proposta_manual_sem_cadencia` → "Acompanhar com o Artur" e `outro` → "Revisar manualmente"; `grep -i luciano` vazio em `scansolo.json` e `config/locales/en.yml`; nenhum número de telefone nos textos.
      Testes: `app/javascript/dashboard/routes/dashboard/scansolo/specs/i18nCompleteness.spec.js` — enumerações novas resolvidas
- [ ] T15 — Frontend: clientes de API e stores Pinia
      Arquivos: `app/javascript/dashboard/api/scansoloReports.js`, `app/javascript/dashboard/api/scansoloQuoteRequests.js`, `app/javascript/dashboard/api/scansoloPipelineOpportunities.js`, `app/javascript/dashboard/store/scansolo/reports.js`, `app/javascript/dashboard/store/scansolo/pipelineOpportunities.js`
      Mudança: `ScanSoloReportsAPI.get({ period, anchor })` (`scan_solo/reports`, accountScoped); `ScanSoloQuoteRequestsAPI.bulkMarkHandledManually(ids)` (POST `scan_solo/quote_requests/handled_manually` com `{ opportunity_ids }`); `markHandledManually(id)` no cliente de oportunidades; store `reports` (`fetchReport`, `report`, `uiFlags.fetching`, `error`, camelcase profundo); `markHandledManually` no store de oportunidades faz `upsertOpportunity` com a resposta; 422 propaga.
      Cobre: CT-01, CT-03, CT-04, UI-02, UI-08, UI-09
      Acceptance criteria: os clientes chamam exatamente as URLs/corpos do `openapi.yaml`; `fetchReport` guarda a resposta camelizada e liga/desliga `uiFlags.fetching`; erro fica em `error`; `markHandledManually` substitui o card no estado; os specs passam.
      Testes: `app/javascript/dashboard/api/specs/scansoloReports.spec.js` — URL/params; `app/javascript/dashboard/store/scansolo/specs/reports.spec.js` — sucesso/erro; `app/javascript/dashboard/store/scansolo/specs/pipelineOpportunities.spec.js` — `markHandledManually`

## Phase 9: Telas

Antes de implementar, leia:
1. `.spec/features/scansolo-relatorios-fonte-unica/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-relatorios-fonte-unica/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-relatorios-fonte-unica/openapi.yaml` — formas consumidas pelas telas

- [ ] T16 — Tela Relatórios + módulo `reports` no menu
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/scansoloModules.js`, `app/javascript/dashboard/routes/dashboard/scansolo/index.js`, `app/javascript/dashboard/routes/dashboard/scansolo/reports/Reports.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/reports/reportPeriods.js`, `app/javascript/dashboard/routes/dashboard/scansolo/reports/ReportKpiCard.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/reports/ReportFunnel.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/reports/ReportStalledTable.vue`
      Mudança: módulo `reports` (`scansolo_reports_index`, `i-lucide-bar-chart-3`) em `SCANSOLO_MODULES` (comentário 6 → 7) e `MODULE_COMPONENTS.reports`; abas Semana|Mês (`components-next/tabbar`) e seletor (semana atual + 2 anteriores, mês atual + anterior, intervalos pt-BR calculados em `America/Sao_Paulo` com `date-fns-tz`), abre na semana atual; KPIs com valor anterior e aviso "dados congelados em <generated_at>" só com `source = snapshot`; funil 8 etapas; tabela de parados agrupada por etapa com link de detalhe, dias desde `lastCustomerInteractionAt || createdAt`, rótulos i18n; estados carregando/erro (tentar de novo)/vazio com `ScanSoloListState`.
      Cobre: UI-01, UI-02, UI-03, UI-04, UI-05, UI-10
      Acceptance criteria: `navigation.spec.js` passa com 7 módulos e `scansolo_reports_index` resolve para `Reports.vue` (não `ScanSoloComingSoonPage`); 3 opções na aba Semana e 2 na aba Mês; selecionar a semana anterior chama a API com `period=week` e `anchor` = segunda dessa semana; cada KPI e valor anterior renderizados; aviso só com `source = "snapshot"`; 8 linhas de funil na ordem de `SCANSOLO_PIPELINE_STAGES`; 1 linha por parado com motivo e ação traduzidos (inclusive `proposta_manual_sem_cadencia` e `outro`), dias a partir de `createdAt` quando a interação é null, link para `scansolo_pipeline_opportunity_detail`; os 3 estados aparecem; sem CSS custom/scoped/inline.
      Testes: `app/javascript/dashboard/routes/dashboard/scansolo/reports/specs/Reports.spec.js` — UI-02..UI-05, UI-10; `app/javascript/dashboard/routes/dashboard/scansolo/reports/specs/reportPeriods.spec.js` — fronteiras com TZ=UTC; `app/javascript/dashboard/routes/dashboard/scansolo/specs/navigation.spec.js` — 7 módulos
- [ ] T17 — Kanban e detalhe: `commercial_status`, filtro, regra de parado e ação unitária
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/KanbanBoard.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/OpportunityDetail.vue`, `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/pipelineConstants.js`, `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/MarkHandledManuallyButton.vue`
      Mudança: `isStaleOpportunity(opportunity, now)` em `pipelineConstants.js` (não terminal e `lastCustomerInteractionAt || createdAt` há ≥ 48 h) usado pelo selo Inativo; rótulo do card e do detalhe por `commercialStatus` com `COMMERCIAL_STATUS_LABELS`; filtro de situação comercial no Kanban (padrão "Todas"); "Encaminhado ao Artur em <data>" no detalhe só com `commercialForwardedAt`; remover `commercialStatusKey` de KanbanBoard.vue e OpportunityDetail.vue; `MarkHandledManuallyButton.vue` (visível só com `aguardando_artur` e etapa `qualificado`/`proposta_enviada`, `ScanSoloConfirmDialog` dizendo que nada é enviado agora e que a cadência pós-proposta seguirá, chama CT-03, 422 → mensagem i18n do código) no card e no detalhe.
      Cobre: RF-03, RF-04, UI-06, UI-07, UI-08
      Acceptance criteria: `grep commercialStatusKey` em `KanbanBoard.vue` e `OpportunityDetail.vue` não encontra nada; com 3 oportunidades de situações diferentes, filtrar `aguardando_artur` mostra 1 card e "Todas" mostra 3; rótulo de `proposta_enviada_manual` aparece no card e no detalhe; data de encaminhamento só quando o campo não é null; `isStaleOpportunity` dá o mesmo resultado que o spec Ruby de T03 nos casos (a)–(c) do RF-04; botão só no estado elegível; cancelar não chama a API; confirmar chama CT-03; 422 `quote_request_closed` mostra a mensagem correspondente.
      Testes: `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/specs/KanbanBoard.spec.js` — filtro, rótulo, selo; `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/specs/OpportunityDetail.spec.js` — rótulo e data; `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/specs/MarkHandledManuallyButton.spec.js` — visibilidade, cancelar, confirmar, 422; `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/specs/pipelineConstants.spec.js` — casos do RF-04
- [ ] T18 — Lista em lote dos pedidos aguardando o Artur
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/proposals/QuoteRepliesPending.vue`
      Mudança: seção com as oportunidades `commercialStatus === 'aguardando_artur'`, checkbox por item e "selecionar todos" (`components-next/checkbox`), botão "Marcar selecionados como proposta enviada manualmente", `ScanSoloConfirmDialog` com a quantidade e o aviso de que nenhuma mensagem será enviada e nenhuma cadência pós-proposta será iniciada; confirmar → `bulkMarkHandledManually(ids)`; resultado por item (`handled` ou rótulo do código); recarrega as oportunidades. Sem telefone/e-mail.
      Cobre: UI-09, RF-18
      Acceptance criteria: selecionar 2 de 3 itens e confirmar envia `opportunity_ids` com exatamente os 2 ids; o resultado de cada item é renderizado com o rótulo i18n; cancelar não chama a API; só aparecem oportunidades `aguardando_artur`.
      Testes: `app/javascript/dashboard/routes/dashboard/scansolo/proposals/specs/QuoteRepliesPending.spec.js` — seleção, envio, resultado por item
