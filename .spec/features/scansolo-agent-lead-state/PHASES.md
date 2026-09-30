# Phases: scansolo-agent-lead-state

Gerado por /plan a partir de PLAN.md — view executável para `./ralph.sh .spec/features/scansolo-agent-lead-state/PHASES.md`.

Regras transversais (de `AGENTS.md`/`CLAUDE.md`, `docs/agents/architecture.md`, `docs/agents/domain_rules.md`, `docs/agents/data_model.md`, `docs/agents/coding_guidelines.md`):
- Services são donos de regras, transações, locks e auditoria. Controller só pré-carrega, projeta e renderiza; jbuilder só formata.
- Saída do modelo → efeito somente via ações registradas (`Registry` → `Executor`), com `opportunity_id`/`conversation_id` injetados pelo turno.
- `ScanSolo::Pipeline::StageTransitionService` é o único escritor de etapa.
- `ScanSolo::Qualification::FieldResolver` é o único leitor de "satisfeito?".
- `ScanSolo::LeadState::Writer` é o único escritor do estado do lead e do histórico (append-only).
- Tabelas 1:1 `scan_solo_*` só aditivas, sem colunas em tabelas do Chatwoot.
- Estilo: classe compacta `class ScanSolo::...`, 1 classe por arquivo, ≤150 colunas, header comment com RF/CT/RNF.
- 0 referências a `enterprise/` ou `Captain::`.
- Specs Ruby e rubocop: `docker exec scansolo-phase2-test sh -c 'cd /app && bundle exec rspec <paths>'` (idem `bundle exec rubocop <paths>`). Após a Phase 1: `docker exec scansolo-phase2-test sh -c 'cd /app && bundle install && RAILS_ENV=test bundle exec rails db:migrate'`.

## Phase 1: Fundação — tabelas, catálogo, gem e schema de saída

Antes de implementar, leia:
1. `.spec/features/scansolo-agent-lead-state/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-agent-lead-state/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T01 — Tabelas e modelos do estado do lead
      Arquivos: `db/migrate/20260929000001_create_scan_solo_lead_states.rb` (novo), `db/migrate/20260929000002_create_scan_solo_lead_state_events.rb` (novo), `db/schema.rb`, `app/models/scan_solo/lead_state.rb` (novo), `app/models/scan_solo/lead_state_event.rb` (novo), `app/models/scan_solo/pipeline_opportunity.rb`, `spec/models/scan_solo/lead_state_spec.rb` (novo), `spec/models/scan_solo/lead_state_event_spec.rb` (novo)
      Mudança: migrações só `create_table`. `scan_solo_lead_states`: `opportunity_id` único, `intent`, `qualification_status` enum `em_andamento 0, concluida 1`, `qualification_completed_at`, `next_action`, `next_action_recorded_at`, `next_action_source_message_id`, `authorized_actions` jsonb `[]`, `fields` jsonb `{}`, timestamps. `scan_solo_lead_state_events`: `lead_state_id`, `subject` (`field|intent|next_action`), `key`, `previous_value`, `previous_status`, `new_value`, `new_status`, `source_message_id`, `source_attachment_id`, `created_at` só. `LeadState` com `INTENTS` (10), `NEXT_ACTIONS` (5), `FIELD_STATUSES`, `DEFAULT_NEXT_ACTION_BY_INTENT` (tabela RF-15 + `nil` → `aguardar_cliente`) e validações. `LeadStateEvent#readonly?` = `persisted?`. `PipelineOpportunity has_one :lead_state` (`dependent: :destroy`).
      Cobre: RF-01, RF-06, RF-14, RF-21, RF-23, RF-24, RNF-01, RNF-06
      Acceptance criteria: as migrações não contêm `remove_column`/`rename_column`/`drop_table`/`change_column`; 2º `LeadState` para a mesma oportunidade é inválido; `intent`/`next_action` fora da lista são inválidos; `DEFAULT_NEXT_ACTION_BY_INTENT` tem 11 entradas conforme RF-15; `update!`/`destroy` num `LeadStateEvent` persistido levanta `ActiveRecord::ReadOnlyRecord`.
      Testes: `spec/models/scan_solo/lead_state_spec.rb`, `spec/models/scan_solo/lead_state_event_spec.rb` — unicidade, enums, tabela padrão, somente leitura.
- [ ] T02 — Catálogo fechado RF-02 no `FieldResolver`
      Arquivos: `app/services/scan_solo/qualification/field_resolver.rb`, `spec/services/scan_solo/qualification/field_resolver_spec.rb`
      Mudança: constante `CATALOG` (34 `{key, block, label}` na ordem RF-02), `CATALOG_KEYS`, `BLOCKS`. Acrescentar ao final de `ALIASES` as chaves novas com o rótulo RF-02 como alias e os rótulos novos das chaves existentes ("Contato", "Empresa / razão social", "E-mail principal", "Objetivo", "Link", "Profundidade de investigação", "Integração"), sem reordenar as linhas existentes. `MAKE_KEYS`/`NATIVE` inalterados.
      Cobre: RF-02
      Acceptance criteria: `CATALOG.size == 34`; cada rótulo RF-02 resolve para sua chave; `"Prazo para proposta"` não resolve para `prazo_desejado`; `"E-mail para envio"` não resolve para `email`; `"Objetivo do serviço"` → `tipo_intervencao`; nenhuma grafia normalizada pertence a 2 chaves; exemplos existentes verdes.
      Testes: `spec/services/scan_solo/qualification/field_resolver_spec.rb` — tabela de rótulos, não colisão, exemplos existentes.
- [ ] T03 — Dependência `pdf-reader`
      Arquivos: `Gemfile`, `Gemfile.lock`
      Mudança: `gem 'pdf-reader'` no grupo default; `docker exec scansolo-phase2-test sh -c 'cd /app && bundle install'`. Nenhuma outra gem.
      Cobre: RF-19
      Acceptance criteria: `Gemfile.lock` contém `pdf-reader`; `docker exec scansolo-phase2-test sh -c 'cd /app && bundle exec ruby -e "require %q(pdf-reader); puts Gem.loaded_specs[%q(pdf-reader)].version"'` imprime `2.16.0`; nenhuma outra gem adicionada.
      Testes: comando acima.
- [ ] T04 — Saída do modelo exige `asked_fields` e `summary` (CT-02)
      Arquivos: `app/services/scan_solo/ai_turn/model_invoker.rb`, `app/services/scan_solo/test_mode/mock_llm_provider.rb`, `spec/services/scan_solo/ai_turn/model_invoker_spec.rb`, `spec/services/scan_solo/test_mode/mock_llm_provider_spec.rb`
      Mudança: `build_result` levanta `InvalidOutputError` sem `asked_fields` (Array de String) ou sem `summary` (boolean); `Result` ganha `asked_fields`/`summary`. `MockLlmProvider.call` ganha `fixture_asked_fields: []`, `fixture_summary: false` e devolve as 4 chaves.
      Cobre: RF-10, CT-02
      Acceptance criteria: saída sem `asked_fields`, sem `summary` ou com `summary: "sim"` → `InvalidOutputError`; saída completa → `Result#asked_fields`/`#summary` preenchidos; mock sem fixtures devolve `asked_fields: []` e `summary: false`.
      Testes: `spec/services/scan_solo/ai_turn/model_invoker_spec.rb`, `spec/services/scan_solo/test_mode/mock_llm_provider_spec.rb` — schema obrigatório e defaults do mock.

## Phase 2: Escritor, resolvedor estendido e leitor de anexos

Antes de implementar, leia:
1. `.spec/features/scansolo-agent-lead-state/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-agent-lead-state/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T05 — `ScanSolo::LeadState::Writer` (único escritor)
      Arquivos: `app/services/scan_solo/lead_state/writer.rb` (novo), `spec/services/scan_solo/lead_state/writer_spec.rb` (novo)
      Mudança: `Writer.new(lead_state:)` com `lock!` e 1 `save!` por operação, dentro da transação do chamador. `apply_field!(key:, value:, status:, source_message_id:, source_attachment_id: nil)`: chave fora de `CATALOG_KEYS` → `ArgumentError`; valor em branco → `:ignored`; confirmado vigente + inferido → `:kept_confirmed`; mesmo valor e status → `:unchanged`; senão grava valor, status, origem e `updated_at` + 1 evento `field` (previous/new) → `:applied`. `set_intent!` (evento `intent` se mudou), `record_next_action!(value:, source_message_id:)` (evento `next_action`; origem nula só no backfill), `authorize_action!` (sem duplicar, sem evento), `complete!(at:)` (levanta se já concluída), `self.applicable?(current_status:, new_status:)`. Eventos só `create!`.
      Cobre: RF-06, RF-07, RF-14, RF-21, RF-23, RF-24, RNF-06
      Acceptance criteria: `tempo_integracao` "uma diária" confirmado → "30 minutos no mesmo dia" deixa vigente o novo `confirmado` e evento com previous "uma diária", mantendo o evento anterior com a origem original; inferido "RJ" sobre confirmado "Rio/RJ" → inalterado; inferido sobre faltante → gravado `inferido`; inferido→confirmado com mesmo valor → 1 evento; `orcamento`→`convite_cotacao` → 2 eventos de intenção; autorização repetida → 1 entrada; `complete!` 2× levanta; `record_next_action!(value: 'aguardar_cliente', source_message_id: nil)` → gravado com origem nula e 1 evento; toda mudança gera exatamente 1 evento.
      Testes: `spec/services/scan_solo/lead_state/writer_spec.rb` — casos acima.
- [ ] T06 — `FieldResolver` lê o estado do lead (satisfeito ⇔ confirmado)
      Arquivos: `app/services/scan_solo/qualification/field_resolver.rb`, `spec/services/scan_solo/qualification/field_resolver_spec.rb`, `app/services/scan_solo/ai_turn/context_assembler.rb`, `app/services/scan_solo/actions/qualification_field_action.rb`, `app/services/scan_solo/cadence/reply_completeness_detector.rb`, `app/services/scan_solo/proposal/generate_service.rb`, `app/services/scan_solo/proposal/make_provider.rb`, `app/services/scan_solo/handoff/handoff_service.rb`
      Mudança: `self.call(opportunity:, config:)` (contato = `opportunity.contact`, `lead_state` obrigatório, sem guarda). `Field` ganha `status`/`classification`; satisfeito ⇔ `confirmado` no estado; rótulo fora do catálogo nunca satisfeito. Valor: estado (não faltante) → nativo → `custom_attributes` (RF-21). Público `self.contact_value(contact:, canonical_key:)`. `make_qualification` segue por valor presente (CT-05 inalterado). Novo `proposal_gate_missing_labels` (RF-08 v1.2): `concluida` → obrigatórios com status `faltante` (rótulo fora do catálogo conta como `faltante`); `em_andamento` → `missing_labels`; `satisfied`/`missing_labels` não mudam. `GenerateService#missing_required_fields` usa `proposal_gate_missing_labels`. Os 6 call sites trocam só a chamada (`HandoffService` busca a oportunidade por `conversation_id`; sem oportunidade → `nenhum`).
      Cobre: RF-04, RF-08, RF-15, RNF-02
      Acceptance criteria: `name` nativo + `nome` inferido → "Nome" não satisfeito com valor "Milena (WhatsApp)"; `nome` confirmado "Milena Souza" no estado → valor "Milena Souza" e satisfeito; rótulo `budget` → insatisfeito; 2 chamadas iguais com LLM/HTTP stubados para levantar; `grep -n "FieldResolver.call(contact:" app` vazio; config exige `Área`: `concluida` + `area` `inferido` → `proposal_gate_missing_labels == []` e `missing_labels == ['Área']`, `concluida` + `area` `faltante` → `['Área']`, `em_andamento` + `area` `inferido` → `['Área']`, `concluida` + rótulo `budget` → `['budget']`; `generate_service.rb` chama `proposal_gate_missing_labels`.
      Testes: `spec/services/scan_solo/qualification/field_resolver_spec.rb` — satisfação por status, precedência de valor, fora do catálogo, determinismo, predicado do gate.
- [ ] T07 — Leitor de anexos, localização, PDF e URL de mapa
      Arquivos: `app/services/scan_solo/ai_turn/attachment_reader.rb` (novo), `spec/services/scan_solo/ai_turn/attachment_reader_spec.rb` (novo), `spec/fixtures/files/scansolo/lead_state_company.pdf` (novo), `spec/fixtures/files/scansolo/lead_state_scanned.pdf` (novo), `spec/fixtures/files/scansolo/lead_state_11_pages.pdf` (novo), `spec/fixtures/files/scansolo/lead_state_corrupt.pdf` (novo)
      Mudança: `AttachmentReader.call(message:)` puro → `Result(updates:, evidence:, urls:)`. `location` → `link_local` (`external_url` ou `https://www.google.com/maps?q=<lat>,<long>`). PDF: `byte_size` ≤ 10 MB, `PDF::Reader` com ≤ 10 páginas, regex de CNPJ → `cnpj`, rótulo razão social → `empresa`, rótulo endereço → `endereco_obra`. URLs do texto: host de mapa (`google.*/maps`, `maps.google.*`, `goo.gl/maps`, `maps.app.goo.gl`) → `link_local` sem anexo; demais só em `urls`. `evidence` por anexo `{attachment_id, file_type, file_name, extracted, reason}` com `unsupported_type|too_large|too_many_pages|no_extractable_text|extraction_error: <classe>`. Sem LLM nem HTTP.
      Cobre: RF-17, RF-18, RF-18a, RF-19, RF-20, RNF-02
      Acceptance criteria: localização lat -22.9/long -43.2 sem `external_url` → update `link_local` com id do anexo; PDF com "12.345.678/0001-90", razão social e endereço → 3 updates; escaneado → 0 updates e `no_extractable_text`; 11 páginas → `too_many_pages`; corrompido → `extraction_error`; "segue o local https://maps.app.goo.gl/abc" → update sem anexo; `https://exemplo.com.br/edital` → 0 updates e URL em `urls`; 0 requisições HTTP (WebMock).
      Testes: `spec/services/scan_solo/ai_turn/attachment_reader_spec.rb` — casos acima.

## Phase 3: Inicialização, projeção, ações e conclusão

Antes de implementar, leia:
1. `.spec/features/scansolo-agent-lead-state/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-agent-lead-state/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T08 — Estado nasce com a oportunidade + backfill aditivo
      Arquivos: `app/services/scan_solo/lead_state/initialize_service.rb` (novo), `app/models/scan_solo/pipeline_opportunity.rb`, `lib/tasks/scansolo.rake`, `spec/services/scan_solo/lead_state/initialize_service_spec.rb` (novo), `spec/services/scan_solo/pipeline/opportunity_bootstrap_service_spec.rb`, `spec/lib/tasks/scansolo_rake_spec.rb`
      Mudança: `InitializeService.call(opportunity:)` → `LeadState.create_or_find_by!`. Só ao inserir, semeia os 34 campos (`FieldResolver.contact_value` presente → `inferido` com evento via `Writer`, senão `faltante`). `PipelineOpportunity after_create` chama o serviço sem `backfilled_at` (sempre `em_andamento`). Rake `scansolo:backfill_lead_states`: fixa `backfilled_at = Time.current`, `where.missing(:lead_state).find_each` → `InitializeService.call(opportunity:, backfilled_at:)`, imprime total; não escreve em `contacts`. Com `backfilled_at` e etapa ∈ `BACKFILL_CONCLUDED_STAGES` (`qualificado proposta_enviada negociacao ganho perdido`) → `Writer#complete!(at: backfilled_at)` + `record_next_action!(value: DEFAULT_NEXT_ACTION_BY_INTENT[nil], source_message_id: nil)`; demais etapas → `em_andamento` sem próxima ação. Sem `StageTransitionService`, `CompletionService`, `PipelineStageEvent` ou `AuditEvent` (RF-01a).
      Cobre: RF-01, RF-01a, RNF-01, RNF-06
      Acceptance criteria: bootstrap com contato `name = "Milena (WhatsApp)"` → 1 estado, 34 campos, `nome` "Milena (WhatsApp)" `inferido`, 33 `faltante`; 2º bootstrap → 1 estado; nenhum `faltante` com valor e nenhum `confirmado`/`inferido` sem valor; oportunidade criada em `ganho` via callback → `em_andamento`; backfill → 100% das oportunidades com 1 estado e 0 campos `confirmado`; `negociacao` com contato `name = "Ana"` → `nome` `inferido`, `concluida`, `completed_at` = instante do backfill, próxima ação `aguardar_cliente` com `source_message_id` nulo, 0 `PipelineStageEvent` e 0 `AuditEvent` novos; `perdido` → `concluida`; `em_qualificacao` → `em_andamento` e próxima ação nula; 2ª execução → 0 criados e estados/eventos inalterados; `contact.custom_attributes` inalterado.
      Testes: `spec/services/scan_solo/lead_state/initialize_service_spec.rb`, `spec/services/scan_solo/pipeline/opportunity_bootstrap_service_spec.rb`, `spec/lib/tasks/scansolo_rake_spec.rb` — seed, idempotência, backfill por etapa, backfill 2×.
- [ ] T09 — Projeção do estado (`lead_state`, elegíveis, bloco Status)
      Arquivos: `app/services/scan_solo/lead_state/projection.rb` (novo), `spec/services/scan_solo/lead_state/projection_spec.rb` (novo)
      Mudança: `Projection.call(opportunity:, config:, pending_updates: [])` pura → Struct `intent, qualification, next_action, authorized_actions, blocks (6, ordem RF-02, campos com key/label/value/status/classification/updated_at/source_*), status {stage, confirmed_fields, missing_fields, next_action, owner_id, last_customer_interaction_at, next_follow_up_at}, history, eligible_keys`. Classificação = chave ∈ `required_canonical_keys`. `confirmed_fields`/`missing_fields` vêm do `FieldResolver`. `next_follow_up_at` = `cadence_enrollments.active.minimum(:next_attempt_at)`. Elegíveis: só `faltante`, obrigatórios antes, ordem RF-02, `[]` se `concluida`. `pending_updates` sobrepostos com `Writer.applicable?`.
      Cobre: RF-03, RF-04, RF-09, RF-15, RF-17, RF-22, RNF-02
      Acceptance criteria: `area` obrigatório + `cnpj`/`empresa` complementares faltantes → elegíveis `area, empresa, cnpj`; obrigatória `inferido` em `missing_fields` e fora de `confirmed_fields`; mudar `owner_id` muda `status.owner_id` sem escrita no estado; `concluida` → `eligible_keys == []`; `pending_updates` com `link_local` → fora dos elegíveis; trocar intenção não muda classificação.
      Testes: `spec/services/scan_solo/lead_state/projection_spec.rb` — casos acima.
- [ ] T10 — Ação registrada `lead_state_update` (CT-03)
      Arquivos: `app/services/scan_solo/actions/lead_state_update_action.rb` (novo), `app/services/scan_solo/actions/registry.rb`, `app/services/scan_solo/ai_turn/input_guardrail.rb`, `app/services/scan_solo/ai_turn/prompt_builder.rb` (só `ACTION_DESCRIPTIONS`), `spec/services/scan_solo/actions/lead_state_update_action_spec.rb` (novo), `spec/services/scan_solo/actions/registry_spec.rb`, `spec/services/scan_solo/ai_turn/input_guardrail_spec.rb`
      Mudança: `CLASSIFICATION = :automatic`; `SCHEMA` fechado com `opportunity_id` (required, turn-scoped), `intent` enum `INTENTS`, `next_action` enum `NEXT_ACTIONS`, `authorized_action` enum `NEXT_ACTIONS`, `interpretation_risk` boolean. `call(params:, actor:, turn:)` → `Writer` com `source_message_id = turn.message_id`; sem efeitos colaterais externos. Adicionar a `HANDLERS`, `InputGuardrail::ALL_ACTIONS` e `ACTION_DESCRIPTIONS['lead_state_update']`.
      Cobre: RF-14, RF-23, RF-24, RF-25, CT-03
      Acceptance criteria: via `Registry.call`, `intent` `orcamento` depois `convite_cotacao` → histórico `orcamento`→`convite_cotacao`; `intent: "xyz"` → `InvalidParamsError`; parâmetro extra → `InvalidParamsError`; `next_action: "proposta"` registrado com origem; `authorized_action: "proposta"` em `authorized_actions` com mensagem de origem; `next_action: "atendimento_humano"` não muda `ai_control_state`; `lead_state_update` ∈ `ALL_ACTIONS` e ofertada.
      Testes: `spec/services/scan_solo/actions/lead_state_update_action_spec.rb`, `spec/services/scan_solo/actions/registry_spec.rb`, `spec/services/scan_solo/ai_turn/input_guardrail_spec.rb`.
- [ ] T11 — `QualificationFieldAction` grava no estado com status, histórico e espelho
      Arquivos: `app/services/scan_solo/actions/qualification_field_action.rb`, `spec/services/scan_solo/actions/qualification_field_action_spec.rb`
      Mudança: `SCHEMA.fields.additionalProperties` = `oneOf [string, {value: string, status: confirmado|inferido} fechado]`; string → `confirmado`. Chave do catálogo → `Writer#apply_field!` (origem `turn.message_id`); aplicado → espelho no `Contact` (nativo só se em branco e válido; não nativo → merge `custom_attributes[canonical]`); `:kept_confirmed` → `not_applied_fields` `confirmed_value_kept`. Rótulo obrigatório fora do catálogo → só espelho; resto → `unrecognized_fields`. Mantém 1 `save!` e `em_contato → em_qualificacao`; remove o ramo `qualificado` (vai para T12). Retorno ganha `state_changes`.
      Cobre: RF-06, RF-07, RF-08, CT-03
      Acceptance criteria: `{area: "800 m²"}` → `area` `confirmado` no estado e `contact.custom_attributes["area"] == "800 m²"`; `name="Milena (WhatsApp)"` + `{nome: "Milena Souza"}` → estado "Milena Souza" `confirmado` e `contact.name` inalterado; `{cidade_uf: {value: "RJ", status: "inferido"}}` sobre confirmado → inalterado e `confirmed_value_kept`; `{x: {value: 1}}` → `InvalidParamsError`; `em_contato` + chave obrigatória → `em_qualificacao`; a ação nunca leva a `qualificado`.
      Testes: `spec/services/scan_solo/actions/qualification_field_action_spec.rb` — casos acima + exemplos existentes ajustados.
- [ ] T12 — `CompletionService` (conclusão única, RF-21)
      Arquivos: `app/services/scan_solo/lead_state/completion_service.rb` (novo), `spec/services/scan_solo/lead_state/completion_service_spec.rb` (novo)
      Mudança: `call(opportunity:, turn:)`: retorna se `concluida` ou se o resolvedor não tem campos ou tem faltantes. Senão `Writer#complete!`; etapa via `StageTransitionService` (`novo_lead`/`em_contato` → `em_qualificacao` → `qualificado`; `em_qualificacao` → `qualificado`; ≥ `qualificado` sem transição); se a próxima ação não foi registrada neste turno → `record_next_action!(DEFAULT_NEXT_ACTION_BY_INTENT[intent], source_message_id: turn.message_id)`; `AuditLogger.record!(event_type: 'lead_state.qualification_completed', correlation_id: turn.correlation_id)`.
      Cobre: RF-21, RF-23, RF-04
      Acceptance criteria: `em_qualificacao` + último obrigatório confirmado → `concluida`, `qualificado`, 1 `PipelineStageEvent`, próxima ação e 1 `AuditEvent`; 2ª chamada → nenhum evento novo; `em_contato` → 2 eventos (`em_contato→em_qualificacao`, `em_qualificacao→qualificado`); intenção `visita` sem next_action → `avaliacao_tecnica`; intenção nula → `aguardar_cliente`; next_action `proposta` do turno preservada; `cnpj` obrigatório `inferido` → não conclui; `proposta_enviada` → sem transição; concluída + config exigindo campo faltante → continua `concluida`.
      Testes: `spec/services/scan_solo/lead_state/completion_service_spec.rb` — casos acima.

## Phase 4: Contexto, validador, API e consumidores

Antes de implementar, leia:
1. `.spec/features/scansolo-agent-lead-state/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-agent-lead-state/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-agent-lead-state/openapi.yaml` — contrato CT-01 (`lead_state`) implementado por T17

- [ ] T13 — `ContextAssembler`: estado do lead e histórico com anexos
      Arquivos: `app/services/scan_solo/ai_turn/context_assembler.rb`, `spec/services/scan_solo/ai_turn/context_assembler_spec.rb`
      Mudança: `call(message:, config:, attachment_reading:, …)`. Nova chave `lead_state_context` = `Projection` (com `pending_updates: attachment_reading.updates`) + `summary_allowed` (há `PipelineStageEvent`, `qualification_completed_at` ou `next_action_recorded_at` posterior à última mensagem outgoing `scansolo_origin = 'ai'`) + `attachment_extraction: attachment_reading.evidence`; sem oportunidade → `NOT_APPLICABLE`. `conversation_history` com `includes(:attachments)` e, por entrada, `attachments [{id, type, file_name, lat, long, link, extracted}]` e `urls`.
      Cobre: RF-09, RF-16, RF-17, RF-20, RF-25
      Acceptance criteria: mensagem só com localização → entrada com tipo `location` e coordenadas; só PDF → tipo `pdf` e nome do arquivo; `lead_state_context` com `eligible_keys`; `summary_allowed` false sem eventos e true com `PipelineStageEvent` após a última resposta de IA; `attachment_extraction` no retorno; nº de queries igual com 1 e 5 anexos.
      Testes: `spec/services/scan_solo/ai_turn/context_assembler_spec.rb` — casos acima.
- [ ] T15 — `OutputValidator`: violações sobre o estado do lead
      Arquivos: `app/services/scan_solo/ai_turn/output_validator.rb`, `spec/services/scan_solo/ai_turn/output_validator_spec.rb`
      Mudança: `call(content:, validated_claims: {}, restricted_information: [], asked_fields: [], lead_state: nil)`. Ordem: violações existentes → `qualification_closed` → `question_limit` (> 2) → `confirmed_field_question` (chave confirmada em `asked_fields` ou lexical: frases terminadas em "?", sem pontuação, `FieldResolver.normalize`, sequência de tokens de grafia com ≥ 2 tokens de campo confirmado) → `field_not_missing` (fora do catálogo ou ≠ `faltante`). `REGENERABLE_VIOLATIONS` com as 4 novas. Pura.
      Cobre: RF-11, RF-12, RF-17, RF-22, RF-24, RF-25, RNF-02
      Acceptance criteria: `data_desejada` confirmado + "Qual a data desejada?" com `[]` → `confirmed_field_question`; `area` confirmado + "Qual a área aproximada?" com `[]` → aceita; `["area"]` → `confirmed_field_question`; "Para 800 m² indicamos o GPR." → aceita; 3 faltantes → `question_limit`; 2 faltantes → aceita; 1 inferido → `field_not_missing`; `"cor_favorita"` → `field_not_missing`; `concluida` + `["bairro"]` → `qualification_closed`, `[]` → aceita; `summary: true` e pedido de confirmação de ação autorizada → aceitos; exemplos existentes verdes.
      Testes: `spec/services/scan_solo/ai_turn/output_validator_spec.rb` — casos acima.
- [ ] T17 — API: `lead_state` em show/update/stage_transitions (CT-01)
      Arquivos: `app/controllers/api/v1/accounts/scan_solo/pipeline_opportunities_controller.rb`, `app/views/api/v1/accounts/scan_solo/pipeline_opportunities/show.json.jbuilder`, `app/views/api/v1/accounts/scan_solo/pipeline_opportunities/update.json.jbuilder`, `app/views/api/v1/accounts/scan_solo/pipeline_opportunities/_lead_state.json.jbuilder` (novo), `spec/requests/api/v1/accounts/scan_solo/pipeline_opportunities_lead_state_spec.rb` (novo)
      Mudança: `set_opportunity` com `includes(:contact, :stage_events, lead_state: :events)`; `show`/`update`/`stage_transitions` (inclusive replay) definem `@lead_state = ScanSolo::LeadState::Projection.call(opportunity: @opportunity, config: ScanSolo::AiAgentConfig.published_for(Current.account))`; `show`/`update` jbuilder acrescentam `lead_state` via partial `_lead_state` no formato de `openapi.yaml` `LeadState`. `_pipeline_opportunity` e `index` intocados; mesma policy e gate 404.
      Cobre: RF-26, RF-03, CT-01, RNF-04, RNF-05
      Acceptance criteria: `show` retorna `lead_state` com 6 blocos, `status`, `intent`, `qualification`, `next_action`, `authorized_actions` e `history`, e os campos atuais inalterados; `scansolo_enabled = false` → 404; `PATCH owner_id` → `lead_state.status.owner_id` novo; `stage_transitions` com `lead_state`; `index` sem `lead_state`; nº de queries de `show` igual com 1 e 50 eventos; `spec/requests/api/v1/accounts/scan_solo/pipeline_opportunities_spec.rb` verde sem modificação.
      Testes: `spec/requests/api/v1/accounts/scan_solo/pipeline_opportunities_lead_state_spec.rb` — casos acima + spec existente.
- [ ] T18 — Consumidores sob a nova semântica + consistência (RF-08)
      Arquivos: `spec/services/scan_solo/qualification/consumer_consistency_spec.rb`, `spec/services/scan_solo/cadence/reply_completeness_detector_spec.rb`, `spec/services/scan_solo/proposal/generate_service_spec.rb`, `spec/services/scan_solo/proposal/make_provider_spec.rb`, `spec/services/scan_solo/handoff/handoff_service_spec.rb`, `spec/requests/api/v1/accounts/scan_solo/proposals_spec.rb` (só o exemplo `generates a proposal version`), `app/services/scan_solo/cadence/reply_completeness_detector.rb`, `app/services/scan_solo/proposal/generate_service.rb`, `app/services/scan_solo/handoff/handoff_service.rb` (só headers)
      Mudança: setups confirmam no estado (via `Writer`) os campos que devem satisfazer. `consumer_consistency_spec`: satisfeitos/faltantes dos 6 consumidores idênticos entre si e a `Projection#status`; assert estático: nenhum dos 6 arquivos lê `lead_state.fields`/status direto. `generate_service_spec`: gate (config exige `Área`) — `concluida` + `area` `inferido` gera versão e `area` segue em `missing_fields`; `concluida` + `faltante` bloqueia; `em_andamento` + `inferido` bloqueia. A consistência compara `satisfied`/`missing_labels`; o predicado do gate é afirmado à parte. `proposals_spec.rb` exemplo 1 (exceção declarada a RNF-04, Q1 resolvida): publica `required_qualification_fields: ['Área']` e confirma `area` no estado; demais exemplos intocados. Headers: "satisfeito = confirmado no estado do lead".
      Cobre: RF-08, RNF-08
      Acceptance criteria: consistency spec verde com conjuntos idênticos e iguais a `lead_state.status`; dado só no `Contact` → faltante em todos os 6; gate: `concluida` + `area` `inferido` → versão gerada, `concluida` + `area` `faltante` → bloqueada, `em_andamento` + `area` `inferido` → bloqueada; `MakeProvider` mantém chaves `MAKE_KEYS` present-only (CT-05); `git diff main -- spec/requests/api/v1/accounts/scan_solo/proposals_spec.rb` restrito ao exemplo 1; specs dos 4 consumidores verdes.
      Testes: os arquivos listados.

## Phase 5: Prompt

Antes de implementar, leia:
1. `.spec/features/scansolo-agent-lead-state/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-agent-lead-state/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T14 — `PromptBuilder`: estado, regras fixas, roteiro, resumo, histórico com anexos, schema, correção
      Arquivos: `app/services/scan_solo/ai_turn/prompt_builder.rb`, `spec/services/scan_solo/ai_turn/prompt_builder_spec.rb`
      Mudança: `CONTINUITY_RULES` regra 2 → "…só depois pergunte no máximo 2 campos, apenas entre os campos elegíveis (faltantes)."; novas regras fixas (antes de `## Regras do agente`): pergunta direta do cliente respondida antes (RF-13), "Não peça nova confirmação para ação já pedida ou autorizada." (RF-24), listar em `asked_fields` as chaves perguntadas. Seção `## Estado do lead`: etapa, status da qualificação, intenção, exatamente 1 linha `Roteiro da intenção:` (`INTENT_SCRIPTS`, 10 + nula), próxima ação, ações autorizadas, confirmados, inferidos `(inferido)`, obrigatórios não confirmados, `Próximos campos elegíveis` (ou "nenhum" + "Qualificação concluída: não faça perguntas de qualificação."). Seção `## Resumo dos dados`: "resumo permitido" ou "resumo não permitido" + exceção fixa condicionada a eventos da resposta. `chat_messages` com descrição de anexos e links (`[mensagem sem texto]` só sem texto e sem anexo). `output_schema` com `asked_fields` (array de string) e `summary` (boolean) em `required`. `previous_violation:` → seção `## Correção obrigatória` com o nome da violação.
      Cobre: RF-09, RF-13, RF-15, RF-16, RF-22, RF-24, RF-25, RF-10, RF-11a, CT-02
      Acceptance criteria: system contém confirmados, inferidos rotulados e elegíveis sem confirmado/inferido; regra com "no máximo 2" e nenhuma com "no máximo um campo"; regra RF-13 com índice < `## Regras do agente`; exatamente 1 linha de roteiro, que muda entre `orcamento` e `envio_documentos`; `concluida` → elegíveis "nenhum"; "resumo não permitido" sem evento e "resumo permitido" com `summary_allowed`; `proposta` listada como autorizada + regra RF-24; localização/PDF no histórico e nenhuma mensagem com anexo como `[mensagem sem texto]`; schema `required` = `reply, actions, asked_fields, summary`; `previous_violation: 'confirmed_field_question'` presente no system.
      Testes: `spec/services/scan_solo/ai_turn/prompt_builder_spec.rb` — casos acima.

## Phase 6: Orquestração do turno

Antes de implementar, leia:
1. `.spec/features/scansolo-agent-lead-state/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-agent-lead-state/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-agent-lead-state/openapi.yaml` — contrato CT-04 (`failure_reason`, `context_snapshot.attachment_extraction`/`output_regeneration`) implementado por T16

- [ ] T16 — Turno em tentativas transacionais com regeneração (RF-05, RF-11a)
      Arquivos: `app/services/scan_solo/ai_turn/turn_orchestrator.rb`, `app/services/scan_solo/ai_turn/attempt_runner.rb` (novo), `spec/services/scan_solo/ai_turn/turn_orchestrator_spec.rb`, `spec/services/scan_solo/ai_turn/turn_orchestrator_actions_spec.rb`, `spec/services/scan_solo/ai_turn/attempt_runner_spec.rb` (novo)
      Mudança: orchestrator chama `AttachmentReader` antes do `ContextAssembler` (evidência persistida no `context_snapshot`), remove o validador pré-lock, faz até 2 tentativas (2ª com `previous_violation:`), cada uma com modelo fora de lock/transação e `send_response` → `extension.with_lock` + recheck → `AttemptRunner`. `AttemptRunner` em `transaction(requires_new: true)`: aplica `pending_updates` (`inferido`), `execute_actions` (movido, mesma idempotency key), `CompletionService`, `Projection` recarregada, `OutputValidator` com `asked_fields` e `lead_state`; bloqueado → `ActiveRecord::Rollback` + `Result(blocked, violation)`; aprovado → `ResponseSender`. Violação regenerável na 1ª → `context_snapshot['output_regeneration']` fora da transação e nova tentativa; 2ª bloqueada ou não regenerável → `fail!("output validation blocked: <v>")`. Exceção de ação → rollback + `failed`.
      Cobre: RF-05, RF-11a, RF-17, RF-18, RF-18a, RF-19, RF-20, RF-21, CT-04
      Acceptance criteria: turno aprovado → 1 chamada de modelo e evento de histórico com `created_at` ≤ resposta; 1ª `confirmed_field_question` e 2ª ok → 2 chamadas, 1 mensagem, `succeeded`, só as ações da 2ª persistidas e violação da 1ª em `context_snapshot.output_regeneration`; 2 rejeições → 2 chamadas, 0 mensagens, `failed` com `output validation blocked: <v2>` e 0 alterações no estado (inclusive campos de PDF); `price` → 1 chamada e `failed`; PDF corrompido → `succeeded` e motivo em `context_snapshot.attachment_extraction`; intenção inválida → `failed` e 0 alterações; suppressed no recheck → 0 alterações.
      Testes: `spec/services/scan_solo/ai_turn/attempt_runner_spec.rb`, `spec/services/scan_solo/ai_turn/turn_orchestrator_spec.rb`, `spec/services/scan_solo/ai_turn/turn_orchestrator_actions_spec.rb` — casos acima.

## Phase 7: Provas de integração e documentação

Antes de implementar, leia:
1. `.spec/features/scansolo-agent-lead-state/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-agent-lead-state/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-agent-lead-state/openapi.yaml` — contratos CT-01/CT-04 referenciados na documentação (T20)

- [ ] T19 — Integração ponta a ponta com `MockLlmProvider`
      Arquivos: `spec/integration/scan_solo/lead_state_turn_spec.rb` (novo), `spec/integration/scan_solo/qualification_continuity_spec.rb`
      Mudança: turnos reais via `TurnOrchestrator.call(message:, llm_provider: ->(**kw) { MockLlmProvider.call(**kw, fixture_actions:, fixture_asked_fields:, fixture_summary:) })` com asserções em `MockLlmProvider.last_payload` e no estado: (a) correção de `tempo_integracao`; (b) pergunta técnica + regra RF-13; (c) oportunidade concluída; (d) regeneração com provider sequencial; (e) PDF + 2 rejeições; (f) URL de mapa sem HTTP; (g) conclusão a partir de `em_contato`; (h) "pode mandar a proposta" autorizada; (i) oportunidade em `negociacao` com estado do backfill → sem requalificação. `qualification_continuity_spec.rb` ajustado a RF-08 (nativo sozinho não satisfaz).
      Cobre: RF-01a, RF-05, RF-06, RF-11a, RF-13, RF-18a, RF-19, RF-21, RF-22, RF-24
      Acceptance criteria: (a) payload seguinte mostra só "30 minutos no mesmo dia" como vigente; (b) `last_payload` tem a pergunta no histórico e a regra no system; (c) elegíveis "nenhum" e `asked_fields: ["bairro"]` → 2 tentativas rejeitadas `qualification_closed`; (d) 2ª chamada contém o nome da violação e 1 mensagem enviada; (e) 0 campos de PDF persistidos e 0 mensagens; (f) `link_local` `inferido` com origem na mensagem e 0 requisições HTTP; (g) 2 `PipelineStageEvent` + 1 `AuditEvent lead_state.qualification_completed`; (h) próximo prompt lista `proposta` como autorizada; (i) elegíveis "nenhum" e `asked_fields: ["nome"]` → 2 tentativas rejeitadas `qualification_closed`, 0 mensagens; spec da feature anterior verde.
      Testes: `spec/integration/scan_solo/lead_state_turn_spec.rb`, `spec/integration/scan_solo/qualification_continuity_spec.rb`.
- [ ] T20 — Documentação e contrato
      Arquivos: `docs/agents/domain_rules.md`, `docs/agents/data_model.md`, `docs/agents/api_contracts.md`
      Mudança: `domain_rules.md` — resolução (satisfeito = confirmado, catálogo 34), prompt (≤ 2 perguntas, `asked_fields`/`summary`, anexos), guardrails (4 violações + 1 regeneração), registry (9 ações, `lead_state_update`), escrita de qualificação (`qualificado` via `CompletionService`), nova seção "Lead state" (com backfill RF-01a e gate de proposta por status). `data_model.md` — 2 tabelas + relação 1-1/1-*. `api_contracts.md` — `lead_state` em show/update/stage_transitions com ponteiro para o `openapi.yaml` desta feature. Editar só as seções citadas (arquivos têm mudanças locais não commitadas).
      Cobre: CT-01
      Acceptance criteria: `grep -n "lead_state" docs/agents/api_contracts.md docs/agents/data_model.md docs/agents/domain_rules.md` encontra as 3; `grep -n "no máximo um\|≤1 missing" docs/agents/domain_rules.md` vazio; `docker exec scansolo-phase2-test sh -c 'cd /app && bundle exec rspec spec/lib/scansolo_*_spec.rb'` verde.
      Testes: `spec/lib/scansolo_*_spec.rb`.

## Phase 8: Gates de qualidade e regressão

Antes de implementar, leia:
1. `.spec/features/scansolo-agent-lead-state/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-agent-lead-state/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T21 — Gates de qualidade e regressão
      Arquivos: nenhum novo (corrige só quebras residuais causadas pela mudança intencional de semântica, fora de `spec/requests` salvo o exemplo de Q1)
      Mudança: rubocop nos `.rb` alterados; `./scripts/ralph-test.sh`; probes RNF-01 (migrações sem operações destrutivas; `db/schema.rb` só com `create_table "scan_solo_lead_state*"`), RNF-03 (`grep -rnE "enterprise/|Captain::"` nos alterados vazio), RNF-04 (`git diff --stat 2254a74ef8 -- spec/requests` só `proposals_spec.rb` e o arquivo novo de T17). RNF-09 (config publicada → catálogo) é passo pré-deploy do Rollout do PLAN, não código.
      Cobre: RNF-01, RNF-03, RNF-04, RNF-05, RNF-07, RNF-08
      Acceptance criteria: base da feature = `2254a74ef8` (pai de `spec: define lead state…`; a `main` local não tem ancestral comum com este branch); `docker exec scansolo-phase2-test sh -c "cd /app && bundle exec rubocop --force-exclusion $(git diff --name-only 2254a74ef8 -- '*.rb' | tr '\n' ' ')"` → 0 offenses (`--force-exclusion` respeita os `Exclude` do `.rubocop.yml`, ex.: `db/schema.rb` gerado); `./scripts/ralph-test.sh` → exit 0; `grep -nE "remove_column|rename_column|drop_table|change_column" db/migrate/20260929*` vazio; `grep -rnE "enterprise/|Captain::"` nos arquivos novos/alterados vazio; `git diff --stat 2254a74ef8 -- spec/requests` lista só `proposals_spec.rb` e `pipeline_opportunities_lead_state_spec.rb`.
      Testes: comandos acima.
