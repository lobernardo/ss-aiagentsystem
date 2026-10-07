# ROADMAP — Operação ScanSolo centralizada no Chatwoot

Versão 1.0 — 2026-10-01. Fonte do objetivo: `.spec/inputs/scansolo-objetivo-operacao-centralizada.md`.
Substitui o fatiamento antigo (slices 2–4 citadas em `.spec/features/scansolo-agent-lead-state/.handoff/confirmed-input.md`).

## Atualização 2026-10-07 — estado real

A feature `.spec/features/scansolo-operacao-centralizada/` (branch `feat/scansolo-operacao-centralizada`, publicada, sem PR) absorveu
as Fatias 2 (proposta ponta a ponta), 3 (origem/cadastro manual) e 4 (interrupção da cadência), e parte da 5 (card enxuto, tela do
lead, "Novo lead") e da 6 (indicador humano no card). `scansolo-proposal-request-e2e` ficou só no SPEC e foi superada por ela.

- Concluído (código + specs): Phases 1–6 e 8–15 do `PHASES.md` (T01–T16, T19–T31, T33–T35, T40) e o fix `e545ce5b03`.
- Pendente (operador/humano): Phase 7 (HG-A/B/C), 16 (HG-D), 17 (Make), 18 (HG-03 + smoke), 19 (`make/REGISTRO-LEGADO.md`, ainda não criado).
- Pendente (código, condicional à Phase 19): Phase 20 / T32 (`PHASES.run-3.md`).
- Seguem abertas: Fatia 5 (menu reorganizado, lista "Leads"), Fatia 6 (pausar/encerrar/reabrir, indicador na lista de conversas),
  Fatias 7 (campos por serviço), 8 (tarefas) e 9 (relatórios).

**Restrições fixas**
- Não mexer na API oficial do WhatsApp (já configurada) nem no agente de IA/treinamento (prompt, base de conhecimento, config publicada). Fatias que precisarem tocar o agente sinalizam isso como decisão explícita.
- Reaproveitar o que existe; só adicionar o que a operação ScanSolo precisa.
- Cada fatia passa pelo `/plan` (SPEC → esclarecimentos → PLAN/PHASES) antes de implementar.

---

## 1. Situação atual × objetivo (verificado no código em 2026-10-01)

| Item do objetivo | Status | O que já existe | Lacuna |
|---|---|---|---|
| §3.1 Lead site/WhatsApp → pipeline → cadência | EXISTE | 1ª mensagem recebida cria oportunidade em `novo_lead` + cadência (`ConversationListener`, `OpportunityBootstrapService`, `StageEntryEnroller`) | Origem não é gravada |
| §3.2 Cadastro manual de lead | NÃO EXISTE | Só o cadastro nativo de **contato** do Chatwoot (não cria lead). API de oportunidade só tem index/show/update | Criação com dedup, origem, etapa e cadência. Oportunidade exige conversa (`conversation_id` NOT NULL/único) |
| Duplicidade | PARCIAL | E-mail/telefone únicos por conta (nativo) | Fluxo "encontrar → vincular contato existente" |
| §4 `lead_source` | NÃO EXISTE | — | Coluna, valores `website`/`manual`, tag, filtro |
| §5 Etapas | EXISTE | 8 etapas idênticas ao alvo | — |
| §6 Card do pipeline | PARCIAL | Nome, etapa, responsável, última interação, próximo follow-up, selo "Inativo" (48h) | Empresa, serviço, cidade/UF, origem, status/tentativa da cadência, "sem interação há X dias", status da proposta, link para o detalhe |
| §7 Tela do lead | PARCIAL | Rota e tela de detalhe existem, mas nada navega até ela e não mostram a qualificação | Dados básicos completos, origem, responsável, blocos de qualificação (o `show` já devolve `lead_state`) |
| §7 Campos GPR | PARCIAL | Catálogo de 34 campos cobre a maioria | Faltam tipo de piso, turno, contato de campo, ART; catálogo não é por serviço |
| §8 Estado estruturado | EXISTE (fatia 1) | `LeadState` com campos, status, histórico, intenção, próxima ação | Consolidar na visão: origem, serviço, cadência, proposta |
| §9 Entrada em cadência | PARCIAL | Automática por etapa (novo_lead, em_contato, em_qualificacao, proposta_enviada) | Entrada manual pela UI |
| §10 Regras de cadência | PARCIAL | Templates por etapa/passo e pausar/retomar/cancelar na UI | Prazos dos passos vêm de seed (não editáveis na UI) |
| §11 Resposta do cliente | PARCIAL | Atualiza última interação; detector cancela cadência quando a resposta completa | Resposta parcial cancela só o próximo envio (risco de follow-up indevido); depende do turno de IA |
| §12 Handoff | PARCIAL | Assumir / devolver à IA, pausa e retomada de cadência, banner na conversa | Pausar, encerrar, reabrir; indicador na lista de conversas |
| §13 Menu ScanSolo | PARCIAL | Pipeline, Agente de IA, Conhecimento, Follow-ups, Propostas, Execuções | Leads, Tarefas, Relatórios, Configurações; reorganização |
| Propostas | PARCIAL | Módulo completo no Rails + cenários Make | Ligação ponta a ponta (Fatia 2) |
| Tarefas operacionais | NÃO EXISTE | `next_action` do lead é o mais próximo | Tudo |
| Indicadores/Relatórios | NÃO EXISTE | Só status técnico e feed de execuções | Tudo |

---

## 2. Novo fatiamento

Ordem pensada por dependência e risco operacional. Cada fatia é entregável sozinha.

### Fatia 2 — `scansolo-proposal-request-e2e` (em andamento)
Objetivo: lead qualificado → rascunho no Make/Drive → aprovação → envio por e-mail (PDF) + aviso WhatsApp.
Estado: SPEC v1.0 pronto (`.spec/features/scansolo-proposal-request-e2e/SPEC.md`); pendentes Q-01..Q-07 (`.handoff/clarifier-questions.md`). Objetivo §: propostas.
Atenção: RF-05a (agente pede e-mail) toca o comportamento do agente — confirmar se é aceitável pela restrição.

### Fatia 3 — `scansolo-lead-origin-manual-entry`
Objetivo §3, §4, §9 (entrada manual).
- `lead_source` estruturado na oportunidade (`website`, `manual`); backfill `website` nas existentes; leads do fluxo atual gravam `website`.
- Cadastro manual dentro do ScanSolo: busca contato por telefone/e-mail → vincula ou cria; cria o lead com origem `manual`, responsável, etapa escolhida; matricula na cadência da etapa (mecanismo existente).
- Decisão necessária: como resolver o vínculo obrigatório com conversa (recomendado: abrir a conversa no inbox WhatsApp oficial do contato, sem mensagem, para a cadência conseguir enviar templates).
- Origem só para identificação/filtro/indicador; não altera cadência.

### Fatia 4 — `scansolo-followup-reliability` (antiga slice 4, ampliada)
Objetivo §9–§11.
- Parar ou recalcular a cadência em toda resposta do cliente, independente do turno de IA (hoje resposta parcial só cancela o próximo envio).
- Regra explícita de "resposta → interrompe / recalcula" por etapa.
- Decisões: cadência para `qualificado` e `negociacao`? Prazos dos passos editáveis na UI ou continuam em seed?

### Fatia 5 — `scansolo-operator-console` (antiga slice 3, reescrita)
Objetivo §5, §6, §7 (visualização), §8 (visão consolidada), §13.
- Menu reorganizado: Pipeline · Leads · Propostas · Tarefas · Relatórios · Automações (Agente de IA, Conhecimento, Follow-ups, Execuções) · Configurações. Itens ainda não construídos não aparecem (ou ficam ocultos) até a fatia deles.
- Card do Kanban com os 13 campos do §6, selo "Sem interação há X dias", tag SITE/COMERCIAL, link para o lead.
- Tela do lead: dados básicos, origem, responsável, etapa, blocos de qualificação do `lead_state` (confirmado/inferido/faltante), cadência (status, tentativa, próximo envio), proposta (status).
- Lista "Leads" (tabela com filtros por origem, etapa, responsável).
- Botão "Novo lead" (usa a API da Fatia 3).

### Fatia 6 — `scansolo-handoff-controls`
Objetivo §12.
- Ações pausar, encerrar, reabrir e devolver à automação, usando os estados que já existem (`paused`, `closed`).
- Indicador de "atendimento humano" na lista de conversas e no card do pipeline.
- Sem mudar o comportamento do agente.

### Fatia 7 — `scansolo-service-qualification-fields`
Objetivo §7 (campos por serviço).
- Novos campos: tipo de piso, turno, contato de campo, necessidade de ART.
- Conjunto de campos por tipo de serviço (GPR etc.).
- ⚠️ Toca o agente (o que ele pergunta). Pela restrição, precisa de decisão: fazer só na visualização/edição manual, ou liberar mudança controlada no agente.

### Fatia 8 — `scansolo-operational-tasks`
Objetivo: tarefas operacionais.
- Tarefa ligada ao lead (tipo, responsável, prazo, status).
- Tarefas automáticas a partir de eventos (ex.: proposta aguardando preenchimento do comercial, handoff aguardando humano, próxima ação registrada).
- Tela "Tarefas" (minhas / da equipe / atrasadas).

### Fatia 9 — `scansolo-commercial-reports`
Objetivo: indicadores.
- Funil por etapa, conversão, tempo por etapa, leads por origem, eficácia de cadência, propostas (geradas/aprovadas/enviadas/ganhas).
- Tela "Relatórios" com filtros por período, origem, responsável.

### Itens soltos do plano antigo
- §16 formulário RFQ → absorvido pela Fatia 3 (cadastro manual) — confirmar.
- §38 migração de domínio → runbook operacional, fora das fatias.
- §39.2 validação com lead real → vira critério de aceite final de cada fatia.

---

## 3. Decisões abertas (antes do `/plan` de cada fatia)
1. Fatia 2: respostas Q-01..Q-07 + tier `complete`; RF-05a pode mexer no agente?
2. Fatia 3: lead manual abre conversa no inbox WhatsApp (recomendado) ou oportunidade passa a existir sem conversa?
3. Fatia 4: cadências para `qualificado`/`negociacao`; prazos editáveis na UI.
4. Fatia 5: itens do menu ainda sem tela — ocultar ou mostrar "em breve"?
5. Fatia 7: campos por serviço só na tela/edição manual ou também no agente?
6. Ordem das fatias (sugerida acima).
