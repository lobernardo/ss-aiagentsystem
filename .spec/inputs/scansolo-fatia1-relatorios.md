# Fatia 1 — Relatórios no menu, fonte única de “encaminhado” e motivos de parada

> Input para `/bc-harness:plan`. Feature: `scansolo-relatorios-fonte-unica`. Base: commit `fe558ba18e` (= produção em 07/11/2026).
> Contexto e decisões do Leo: DECISOES.md (DEC-047..054) e STATUS_ATUAL.md §9 no projeto.
> Nome público do contato comercial: **Artur**. "Luciano" só em código/documentos internos, nunca em mensagem externa, prompt ou KB.
> Nenhum número de telefone no Git: o WhatsApp comercial é config do Agent Center (banco).

## Objetivo
Painel **Relatórios** no menu ScanSOLO com visão **semanal e mensal**, números confiáveis vindos do banco e explicação do **porquê** cada lead parado está parado, etapa a etapa. Somente leitura (exceto a ação manual do item 7).

## Problema atual
- Menu tem 6 módulos (pipeline, agent, knowledge, followups, proposals, executions), sem métricas. Relatórios é a Fatia 9 do ROADMAP, aberta.
- "Encaminhado ao Luciano" só era inferido pelo selo do Kanban; a verdade está em `scan_solo_quote_requests`.
- O relatório “por que parado” foi feito à mão (planilha/artefato), sem regra no código.

## Escopo
1. **`ScanSolo::Reports::CommercialStatus`** (puro): `nao_encaminhado | aguardando_artur (quote_request awaiting_reply/correction_requested) | resposta_recebida (replied) | proposta_em_aprovacao | proposta_enviada | proposta_enviada_manual | escalado_wa` (este último só depois da Fatia 2; tratar como inexistente até lá). Expor `commercial_status` e `commercial_forwarded_at` no JSON da oportunidade e filtro no Kanban.
2. **`ScanSolo::Reports::StallReason`** (puro), uma razão por lead, precedência: `em_atendimento_humano`, `aguardando_artur`, `cadencia_bloqueada_template_meta` (`last_block_reason`: `template_missing`, `params_mismatch`), `followup_vencido_nao_enviado`, `sem_followup_agendado`, `cadencia_concluida_sem_resposta`, `aguardando_resposta_do_lead`, `qualificado_sem_encaminhamento`. “Parado” = 48 h sem interação do lead (regra do selo Inativo). Tabela estática motivo → ação sugerida.
3. **`ScanSolo::Reports::PeriodSummary`** (puro, SQL read-only): leads novos por origem; respondidos; mediana e p90 até a 1ª resposta; turnos de IA por status e motivo; inbound sem turno; cadências por resultado e bloqueio; funil por etapa (ativos × parados); qualificados e encaminhados no período; propostas por status; comparação com o período anterior.
4. **API**: `GET /api/v1/accounts/:account_id/scan_solo/reports?period=week|month&anchor=YYYY-MM-DD` (+ lista de parados por etapa). Permissão igual aos demais módulos.
5. **Snapshot semanal persistido** (`scan_solo_report_snapshots`, jsonb, 1 por conta/semana) gravado por job de sexta de manhã; relatório de semanas passadas lê o snapshot, a semana atual é calculada ao vivo. Período = segunda 00:00 a domingo, fuso `America/Sao_Paulo`.
6. **UI**: módulo `reports` em `scansoloModules.js` (`scansolo_reports_index`, `i-lucide-bar-chart-3`, `SCANSOLO.SIDEBAR.REPORTS`), abas **Semana | Mês**, seletor (semana atual + 2 anteriores; mês atual + anterior), KPIs, funil, tabela de parados por etapa com motivo e ação sugerida.
7. **Envio manual (fase de transição).** Hoje o Artur recebe o pedido por e-mail e envia o orçamento **pessoalmente**, fora do sistema; os pedidos ficam `awaiting_reply` e o lead fica em `qualificado` mesmo já atendido. Entregar a ação humana **“Marcar proposta enviada manualmente”** (Kanban e detalhe do lead, só usuário autenticado): move a oportunidade para `proposta_enviada` via `StageTransitionService` (ator humano, o que enrola a cadência pós-proposta existente), fecha a `QuoteRequest` com novo status aditivo `handled_manually` (+ `handled_manually_at`/`by`), registra auditoria `quote_request.handled_manually` e aparece como `CommercialStatus = proposta_enviada_manual`. Ação em lote para os pedidos legados (os 20 pedidos de 13/10 a 06/11): lista com seleção, sem envio de mensagem a ninguém. Quando o agente passar a enviar, o fluxo automático substitui este caminho sem remover a ação.

## Não escopo
Mudar comportamento do agente, cadências ou templates; enviar mensagens.

## Atenção técnica
- `scan_solo_pipeline_stage_events.from_stage/to_stage` são **string** (`'qualificado'`); `scan_solo_pipeline_opportunities.stage` é enum inteiro.
- Enum de `cadence_attempts.result`: scheduled 0, sent 1, skipped 2, failed 3, cancelled 4, dispatched 5.
- `AiTurn.invocation_status`: 0 pending, 1 suppressed, 2 succeeded, 3 failed.
- `QuoteRequest.status`: awaiting_reply 0, correction_requested 1, replied 2 (novo `handled_manually` deve ser aditivo).
- Não imprimir/retornar conteúdo de mensagem, telefone ou e-mail.

## Critérios de aceite
Cada indicador do painel bate com a consulta SQL de referência (leads novos, respondidos, funil e qualificados da semana, conferidos contra o banco); o motivo de cada lead parado vem do classificador (spec com um caso por motivo); `CommercialStatus` é o único lugar da regra (Kanban, detalhe e relatório o consomem); snapshot idempotente; guard de role como nos outros módulos; a ação manual registra auditoria e não envia mensagem.

## Testes
Services puros com fixtures por motivo; request spec da API com permissões; Vitest da tela e do roteamento/i18n (`i18nCompleteness`, `navigation`).

## Regras fixas (todas as fatias)
Resposta externa única por evento; LLM não controla relógio; re-checar estado antes de envio automático; nada de proposta mock ao cliente nem dado comercial inventado; migrações só aditivas; sem commit/push/merge/deploy sem autorização; specs com `scan_solo` no caminho; `./scripts/ralph-test.sh` verde; i18n só em `config/locales/en.yml` e `i18n/locale/en/scansolo.json` (pt-BR); Vue `<script setup>` + Tailwind + `components-next/`.
