# Phases: scansolo-escalacao-filtrada

Gerado por /plan a partir de PLAN.md — view executável para `./ralph.sh .spec/features/scansolo-escalacao-filtrada/PHASES.md`.

Regras para todas as fases:
- Migrações só aditivas.
- i18n só em `config/locales/en.yml` (conteúdo pt-BR).
- Nenhum telefone real no Git: usar só o fictício `+5511999999999`.
- "Luciano" nunca em string de produto, prompt ou KB; texto externo nomeia só "Artur".
- Não rodar `annotaterb`.
- Camadas (`docs/agents/architecture.md`): `ScanSolo::Commercial::EscalationService` é o único escritor da marca e de `email_redirect_count`. A elegibilidade vive só em `ScanSolo::Commercial::EscalationGate`, chamado só pelo `EscalationService`. Nenhuma guarda repetida na ação, no `Negotiation::RequestService` ou no `AttemptRunner`.

## Phase 1: Aprovação da redação e DEC (gate humano)

Antes de implementar, leia:
1. `.spec/features/scansolo-escalacao-filtrada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-escalacao-filtrada/PLAN.md` — decomposição completa, dependências e riscos

Se a aprovação do Leo não estiver registrada, NÃO marque o item e PARE a execução. Nenhuma fase seguinte pode rodar sem ela.

- [ ] T01 — Aprovação bloqueante da redação da orientação por e-mail (Q-06) e registro da nova DEC
      Arquivos: `.spec/features/scansolo-escalacao-filtrada/APROVACAO.md` (novo); `DECISOES.md` externo (registro feito pelo Leo)
      Mudança: apresentar ao Leo a proposta de redação de `scan_solo.commercial.email_first.{before_qualified,before_qualified_ask,quote_pending,quote_sent}` (textos na T01 do PLAN; entrega do link reutiliza `scan_solo.negotiation.escalation_reply`). Registrar em `APROVACAO.md`: o texto final aprovado por chave, o id da nova DEC, a data e a linha `Aprovado por: Leo`.
      Cobre: RF-01, RF-03, RF-04, RF-10, RNF-05
      Acceptance criteria: `APROVACAO.md` existe com as 4 chaves e seus textos, o id da DEC e a linha literal `Aprovado por: Leo`.
      Testes: n/a (verificação manual do arquivo)

## Phase 2: Schema e gate puro

Antes de implementar, leia:
1. `.spec/features/scansolo-escalacao-filtrada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-escalacao-filtrada/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T02 — Migração aditiva `email_redirect_count` e suporte no modelo
      Arquivos: `db/migrate/20261116100001_add_email_redirect_count_to_scan_solo_pipeline_opportunities.rb` (novo), `db/schema.rb`, `app/models/scan_solo/pipeline_opportunity.rb`, `spec/db/scansolo_migrations_spec.rb`, `spec/models/scan_solo/pipeline_opportunity_escalation_spec.rb`
      Mudança: `add_column :scan_solo_pipeline_opportunities, :email_redirect_count, :integer, null: false, default: 0`, sem backfill. Schema atualizado. Validação numérica inteira >= 0 no modelo, com anotação editada à mão. Contagem do migrations spec 46 → 47.
      Cobre: CT-02, RNF-02
      Acceptance criteria: a migração usa só `add_column`. `db/schema.rb` tem `email_redirect_count` integer `null: false, default: 0`. Valor negativo invalida a oportunidade. `scansolo_migrations_spec` espera 47. `db:migrate`/`db:rollback`/`db:migrate` no banco de teste sem erro.
      Testes: `spec/db/scansolo_migrations_spec.rb` — contagem 47 e aditividade; `spec/models/scan_solo/pipeline_opportunity_escalation_spec.rb` — default 0 e negativo inválido
- [ ] T03 — `ScanSolo::Commercial::EscalationGate` (decisão pura) e spec da matriz
      Arquivos: `app/services/scan_solo/commercial/escalation_gate.rb` (novo), `spec/services/scan_solo/commercial/escalation_gate_spec.rb` (novo)
      Mudança: módulo puro com `QUALIFIED_STAGES = %w[qualificado proposta_enviada negociacao]`, `decide(stage:, quote_sent:, email_redirect_count:, commercial_request:, previously_escalated:)` e `quote_sent?(opportunity)` (= `quote_request&.sent_at.present?`). Ordem de `decide`: sem pedido → `:none`; etapa fora → `:etapa_nao_qualificada`; sem envio → `:orcamento_nao_enviado`; contador 0 → `:primeiro_pedido_email`; senão `:approved`. Sem escrita, LLM ou HTTP.
      Cobre: RF-01, RF-03, RF-04, RF-05, RF-08, RF-11, RNF-03
      Acceptance criteria: a matriz 8 etapas × enviado × contador (0/≥1) × pedido × link anterior (128 combinações) dá `:approved` só para etapa qualificada + enviado + contador ≥1 + pedido, e cada recusa no caso esperado. Duas avaliações dão o mesmo resultado. `quote_sent?` é false sem `QuoteRequest` ou com `sent_at` nulo.
      Testes: `spec/services/scan_solo/commercial/escalation_gate_spec.rb` — matriz completa, determinismo e `quote_sent?`

## Phase 3: Blocos de domínio

Antes de implementar, leia:
1. `.spec/features/scansolo-escalacao-filtrada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-escalacao-filtrada/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-escalacao-filtrada/APROVACAO.md` — redação aprovada (usar literalmente em T06)

- [ ] T04 — `EscalationService` passa pelo gate: recusa estruturada, contador e decisão única por turno
      Arquivos: `app/services/scan_solo/commercial/escalation_service.rb`, `app/services/scan_solo/actions/escalate_to_commercial_action.rb` (comentário), `spec/services/scan_solo/commercial/escalation_service_spec.rb`, `spec/services/scan_solo/actions/escalate_to_commercial_action_spec.rb`
      Mudança: após `lock!`, decisão única por `correlation_id`: audit `commercial.escalated` do turno → resultado aprovado; audit novo `commercial.escalation_refused` do turno → mesma recusa sem novo incremento. Na 1ª decisão do turno, chama `EscalationGate.decide`.
        - `:approved`: comportamento atual (marca, 1 audit, aviso só na 1ª escalação).
        - Recusa: `increment!(:email_redirect_count)` só em `:primeiro_pedido_email`; 1 audit `commercial.escalation_refused` (payload sem telefone); 0 `Publisher`; retorno `{ escalated: false, refusal:, email_redirect_count: }`; nunca levanta exceção.
      Cobre: RF-01, RF-03, RF-04, RF-05, RF-08, RF-11, RF-12, CT-01
      Acceptance criteria:
        - Recusa por etapa ou orçamento: marca nula, contador inalterado, 0 `Publisher`.
        - 1º pedido elegível: contador +1, payload CT-01. Uma 2ª chamada com o mesmo `correlation_id` não incrementa de novo.
        - Aprovado: marca + 1 `commercial.escalated` + 1 `Publisher`. Reenvio já escalado: marca sobrescrita, 1 novo audit, 0 `Publisher`.
        - A ação devolve o hash de recusa sem exceção.
      Testes: `spec/services/scan_solo/commercial/escalation_service_spec.rb` — os cenários acima e o lock existente; `spec/services/scan_solo/actions/escalate_to_commercial_action_spec.rb` — recusa sem exceção
- [ ] T05 — `OutputValidator`: violação `commercial_link_not_allowed`
      Arquivos: `app/services/scan_solo/ai_turn/output_validator.rb`, `spec/services/scan_solo/ai_turn/output_validator_spec.rb`
      Mudança: novo parâmetro `escalation_approved: false`. Logo após `unpublished_contact`, `:commercial_link_not_allowed` quando `commercial_link` presente e (sem aprovação e o conteúdo contém o link) ou (com aprovação e o link aparece mais de 1 vez). O símbolo entra em `REGENERABLE_VIOLATIONS`. O comentário de cabeçalho é atualizado.
      Cobre: RF-09, RF-05, CT-03
      Acceptance criteria: link publicado sem aprovação → `blocked: true` com `commercial_link_not_allowed`. Com aprovação e 1 ocorrência → `blocked: false`. 2 ocorrências → bloqueado. `wa.me` de outro número → `unpublished_contact`. `REGENERABLE_VIOLATIONS` inclui o símbolo.
      Testes: `spec/services/scan_solo/ai_turn/output_validator_spec.rb` — os 4 casos acima
- [ ] T06 — Textos aprovados da orientação por e-mail em `en.yml`
      Arquivos: `config/locales/en.yml`, `spec/lib/scansolo_locale_spec.rb`
      Mudança: adicionar `scan_solo.commercial.email_first.{before_qualified,before_qualified_ask,quote_pending,quote_sent}` exatamente como em `APROVACAO.md`. `escalation_reply` inalterado.
      Cobre: RF-01, RF-02, RF-03, RF-04, RF-14, RNF-05
      Acceptance criteria: as 4 chaves existem com o texto aprovado, interpolam `%{email}` (e `%{fields}` em `before_qualified_ask`) e há 0 `/luciano/i` no escopo `scan_solo`.
      Testes: `spec/lib/scansolo_locale_spec.rb` — presença/interpolação das chaves e ausência do nome interno
- [ ] T07 — `PromptBuilder`: regras fixas da escada e-mail primeiro
      Arquivos: `app/services/scan_solo/ai_turn/prompt_builder.rb`, `spec/services/scan_solo/ai_turn/prompt_builder_spec.rb`
      Mudança: substituir `ESCALATION_RULES` (constante, só com número publicado) pela escada:
        - sinalizar todo pedido comercial ou de humano com `escalate_to_commercial` em qualquer etapa (a aplicação decide);
        - antes de `qualificado`: e-mail publicado + próxima pergunta sem repetir;
        - em etapa qualificada: e-mail primeiro;
        - contato só via `{{LINK_ARTUR}}` e entregue pela aplicação;
        - não repetir o contato em cortesias;
        - manter especialista virtual e transparência.
      Remover os gatilhos 2), 3) e 4) atuais. E-mail interpolado de `config.quote_recipient_email`. `ACTION_DESCRIPTIONS['escalate_to_commercial']` vira "sinalizar". Adicionar `VIOLATION_INSTRUCTIONS['commercial_link_not_allowed']`.
      Cobre: RF-10, RF-11, RF-14, CT-03
      Acceptance criteria: com número publicado, o system message contém as regras novas e o `quote_recipient_email`, e não contém os textos dos gatilhos 2), 3) e 4) antigos. Editar config não remove as regras. `internal_name?` é falso no system message. `correction_block` com `commercial_link_not_allowed` não levanta `KeyError`.
      Testes: `spec/services/scan_solo/ai_turn/prompt_builder_spec.rb` — os casos acima

## Phase 4: Negociação

Antes de implementar, leia:
1. `.spec/features/scansolo-escalacao-filtrada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-escalacao-filtrada/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T08 — `Negotiation::RequestService` alinhado ao gate
      Arquivos: `app/services/scan_solo/negotiation/request_service.rb`, `spec/services/scan_solo/negotiation/request_service_spec.rb`
      Mudança: manter a transição `proposta_enviada → negociacao` e o audit `negotiation.requested` independentes do gate. Com número publicado, delegar ao `EscalationService` (recusa → nenhum `Publisher`). Sem número, inalterado. Devolver o resultado CT-01. Comentário atualizado; nenhuma guarda de etapa repetida.
      Cobre: RF-12, RF-13
      Acceptance criteria:
        - `proposta_enviada` + `sent_at` + contador 0: 1 stage event, 1 `negotiation.requested`, marca nula, contador 1, 0 `Publisher`.
        - Sem `QuoteRequest`: stage event + audit, marca nula, contador 0.
        - `qualificado` + enviado + contador 1: marca + 1 `Publisher` `commercial.escalated`.
        - Sem número: `negotiation.requested` publicado como hoje.
      Testes: `spec/services/scan_solo/negotiation/request_service_spec.rb` — os 4 cenários

## Phase 5: Fiação no turno

Antes de implementar, leia:
1. `.spec/features/scansolo-escalacao-filtrada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-escalacao-filtrada/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T09 — `AttemptRunner`: link só com escalação real, resposta e-mail primeiro e entrada do validador
      Arquivos: `app/services/scan_solo/ai_turn/attempt_runner.rb`, `spec/services/scan_solo/ai_turn/attempt_runner_spec.rb`
      Mudança:
        - `commercial_request_reason` lê o `reason` de `escalate_to_commercial` nos params do modelo (`result.actions`), não no resultado.
        - `escalate_negotiation!` usa `escalation_reply` só se aprovado.
        - Novo `apply_commercial_outcome!` lê a decisão do turno pelos audits do `correlation_id`:
          - aprovado → `escalation_reply` com placeholder + e-mail;
          - `etapa_nao_qualificada` → mantém a resposta do modelo só se contém o e-mail publicado e (sem campo elegível ou `asked_fields` não vazio) e não é fallback; senão `before_qualified_ask` com campos elegíveis (`em_bloco` → `relevant_pending_keys`; progressivo → `eligible_keys.first(1)`) ou `before_qualified`;
          - `orcamento_nao_enviado` → `quote_pending`, prevalecendo sobre `completed_reply`;
          - `primeiro_pedido_email` → `quote_sent`.
        - `resolve_commercial_link!` monta `@commercial_link` sempre (com número) mas só o insere se `escalated_in_attempt?`; senão remove todo placeholder.
        - `validate_reply` passa `escalation_approved: escalated_in_attempt?`.
        - Reusar `EscalationGate::QUALIFIED_STAGES`. 0 chamadas extras ao LLM.
      Cobre: RF-01, RF-02, RF-03, RF-04, RF-05, RF-06, RF-07, RF-08, RF-09, RF-13, RF-14, RNF-01
      Acceptance criteria:
        - `em_contato` + `escalate_to_commercial`: sem marca, sem `wa.me/`, com o `quote_recipient_email`.
        - `em_qualificacao` com faltantes: `asked_fields` ⊆ faltantes e não vazio.
        - Placeholder sem escalação: removido.
        - Aprovado: exatamente 1 `https://wa.me/5511999999999`.
        - Link literal sem aprovação: `blocked` com `commercial_link_not_allowed` e savepoint desfeito (contador e audits revertidos).
        - `proposta_enviada` + `negotiation_requested` recusado: etapa `negociacao` e resposta `quote_sent`.
      Testes: `spec/services/scan_solo/ai_turn/attempt_runner_spec.rb` — os casos acima

## Phase 6: Integração e documentação

Antes de implementar, leia:
1. `.spec/features/scansolo-escalacao-filtrada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-escalacao-filtrada/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T10 — Integração com LLM mockado: os 4 casos reais
      Arquivos: `spec/integration/scan_solo/escalacao_filtrada_spec.rb` (novo)
      Mudança: turnos reais via `TurnOrchestrator` + `MockLlmProvider`, WebMock, número fictício, `EmailAdapter` stubado (setup de `escalacao_comercial_wame_spec.rb`), estado limpo. Cenários:
        - Daiane (`em_contato`, valor de locação; variante com link literal);
        - Alexandre (`em_qualificacao`, faltando profundidade e prazo);
        - Azanis (`em_qualificacao`, 6 `reason` + `negotiation_requested`);
        - CSI (`qualificado` + `sent_at`): 1º pedido, 2º pedido, "Ok", "obrigado", novo pedido explícito;
        - qualificado sem orçamento;
        - `proposta_enviada` + negociação com e sem `sent_at`.
      Asserções RF-14 em todos os turnos; RF-15 via `AttemptPrecheck`; RF-16 via `commercial_status`; RF-12 por contagem de `Publisher`.
      Cobre: RF-01, RF-02, RF-03, RF-04, RF-05, RF-06, RF-07, RF-08, RF-09, RF-12, RF-13, RF-14, RF-15, RF-16
      Acceptance criteria:
        - Daiane, Alexandre e Azanis: sem marca, contador inalterado, mensagem com e-mail e sem `wa.me/`; Alexandre com `asked_fields` ⊆ faltantes e não vazio.
        - CSI: 1º pedido contador 1 sem link; 2º com marca, 1 `commercial.escalated`, 1 `Publisher` e exatamente 1 `wa.me/`; "Ok"/"obrigado" sem `wa.me/` e 0 eventos novos; pedido explícito posterior com marca sobrescrita, 1 audit, 1 `wa.me/` e 0 `Publisher`.
        - Link literal em `em_contato`: 0 mensagens com `wa.me/`.
        - Exatamente 1 mensagem outgoing por turno e "Luciano" ausente.
        - Só CSI termina `escalado_wa`.
        - `AttemptPrecheck` não defere o lead orientado.
      Testes: `spec/integration/scan_solo/escalacao_filtrada_spec.rb` — os cenários acima
- [ ] T12 — Atualização documental (item próprio)
      Arquivos: `docs/agents/domain_rules.md`, `docs/agents/data_model.md`, `docs/agents/architecture.md`, `.spec/features/scansolo-escalacao-filtrada/DOCS-EXTERNOS.md` (novo)
      Mudança:
        - `domain_rules.md`: gate, contador, decisão única por turno, recusa CT-01, link condicionado, `commercial_link_not_allowed` e recusa na negociação.
        - `data_model.md`: a coluna nova e a contagem de migrações.
        - `architecture.md`: `EscalationGate` no fluxo do turno.
        - `DOCS-EXTERNOS.md`: checklist para o Leo de `DECISOES.md`, `STATUS_ATUAL.md`, `claude/FUNCIONAMENTO_ATUAL_*.md`, `CHANGELOG.md`, `claude/AGENTE_CONFIG_V4.md` e `BACKLOG.md` (incluindo a correção manual pós-deploy de Daiane, Alexandre e Azanis), com o conteúdo a incluir em cada um.
      Editar sobre as alterações locais não commitadas, sem revertê-las.
      Cobre: RF-10 (documentação do entregável)
      Acceptance criteria: `email_redirect_count` aparece em `data_model.md` e `domain_rules.md`; `commercial_link_not_allowed` aparece em `domain_rules.md`; `DOCS-EXTERNOS.md` lista os 6 documentos externos.
      Testes: n/a (verificação por `grep`)

## Phase 7: Regressão e suíte completa

Antes de implementar, leia:
1. `.spec/features/scansolo-escalacao-filtrada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-escalacao-filtrada/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T11 — Regressão: specs que codificam o comportamento antigo, relatórios e suíte completa
      Arquivos: `spec/integration/scan_solo/escalacao_comercial_wame_spec.rb`, `spec/services/scan_solo/ai_turn/turn_orchestrator_actions_spec.rb` (se afetado), `spec/services/scan_solo/cadence/attempt_precheck_spec.rb`, `spec/services/scan_solo/reports/commercial_status_spec.rb`, `spec/services/scan_solo/reports/report_builder_spec.rb`, `spec/requests/api/v1/accounts/scan_solo/pipeline_opportunities_spec.rb` (se afetado)
      Mudança:
        - Reescrever só as expectativas de escalação fora da etapa qualificada ou sem insistência. Em `escalacao_comercial_wame_spec`, (a) em `em_contato` passa a esperar e-mail; (b), (c2) e (e) partem de etapa qualificada com `sent_at` e contador ≥1.
        - Specs de takeover humano e de cadência ficam sem alteração.
        - Adicionar ao `attempt_precheck_spec` um lead `em_qualificacao` com contador 1 e sem marca → sem defer.
        - Rodar `./scripts/ralph-test.sh` e `bundle exec rubocop --force-exclusion` nos arquivos Ruby tocados.
      Cobre: RF-15, RF-16, RNF-04
      Acceptance criteria: `./scripts/ralph-test.sh` com 0 falhas; specs de takeover humano sem diff; rubocop com 0 ofensas nos arquivos tocados; nenhuma asserção de relatório relaxada.
      Testes: suíte completa via `./scripts/ralph-test.sh`; `spec/services/scan_solo/cadence/attempt_precheck_spec.rb` — lead orientado sem defer
