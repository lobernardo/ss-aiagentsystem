# Phases: scansolo-agent-qualification-continuity

Gerado por /plan a partir de PLAN.md — view executável para `./ralph.sh .spec/features/scansolo-agent-qualification-continuity/PHASES.md`.

Regras transversais (de `AGENTS.md`/`CLAUDE.md`, `docs/agents/architecture.md`, `docs/agents/domain_rules.md`, `docs/agents/coding_guidelines.md`): services possuem toda regra e transição; nenhum controller/jbuilder/model muda; `ScanSolo::Pipeline::StageTransitionService` continua o único writer de etapa; `Actions::Executor`/`Registry` sem novo chamador e `SCHEMA` da ação inalterado; um único resolvedor (`ScanSolo::Qualification::FieldResolver`) — nenhum consumidor reimplementa presença de campo; classe compacta `class ScanSolo::...`; 0 referências a `enterprise/` ou `Captain::`; 0 migrations; nenhuma chave existente de `custom_attributes` reescrita/apagada. Specs Ruby e rubocop: `docker exec scansolo-phase2-test sh -c 'cd /app && bundle exec rspec <paths>'` (idem `bundle exec rubocop <paths>`).

## Phase 1: Fundação — resolvedor, regras fixas do prompt, housekeeping

Antes de implementar, leia:
1. `.spec/features/scansolo-agent-qualification-continuity/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-agent-qualification-continuity/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T01 — Resolvedor canônico `ScanSolo::Qualification::FieldResolver`
      Arquivos: `app/services/scan_solo/qualification/field_resolver.rb` (novo), `spec/services/scan_solo/qualification/field_resolver_spec.rb` (novo)
      Mudança: constantes congeladas `ALIASES` (tabela RF-04 na ordem, canônica também aceita), `NATIVE` (`nome→name`, `email→email`, `telefone→phone_number`), `MAKE_KEYS` (10 chaves); `self.normalize` (transliterate, trim, downcase, separadores `_ - espaço /` colapsados e unidos por `_`); `self.canonical_key` (alias ou normalizado — RF-05); `Field` Struct (`label, canonical_key, value, origin, satisfied`); `self.call(contact:, config:)` com `fields` na ordem da config, `missing_labels`, `collected`, `required_canonical_keys`, `make_qualification` (10 chaves independentemente da config, só presentes, sem `integracao_seguranca`/RF-05). Nativo presente = origem `native`; senão `custom_attributes` com precedência RF-21 (canônica exata > rótulo exato > aliases na ordem da tabela > lexicográfica). Sem ler `messages`, sem LLM/HTTP/regex de texto livre, sem escrita.
      Cobre: RF-01, RF-02, RF-03, RF-04, RF-05, RF-06, RF-21, RNF-01, RNF-03, RNF-06
      Depende de: nenhuma
      Acceptance criteria: `name="Leonardo"` + `"Nome"` → `nome`, `"Leonardo"`, `native`, satisfeito; campo sem dado → insatisfeito sem valor; `"Cidade / UF"`, `"cidade_uf"`, `" CIDADE/UF "`, `"cidade-uf"`, `"cidade uf"` normalizam igual; todas as grafias do RF-04 resolvem para a canônica; `"Orçamento"` + `{"orcamento"=>"50k"}` satisfeito; `{"Cidade / UF"=>"Niterói/RJ","cidade_uf"=>"Rio/RJ"}` → `"Rio/RJ"`; `{"Cidade / UF"=>"Niterói/RJ","cidade"=>"Rio"}` → `"Niterói/RJ"`; com LLM/HTTP stubados para levantar a resolução passa e duas chamadas retornam igual; arquivo sem `enterprise`/`Captain::`.
      Testes: `spec/services/scan_solo/qualification/field_resolver_spec.rb` — nativo, fallback custom, normalização, tabela-driven de aliases, RF-05, precedência RF-21, chaves do Make satisfazem rótulos da config v2, `make_qualification` sem `nil`, determinismo.
- [ ] T02 — Diretiva rubocop inline no spec de ingestão (CRLF)
      Arquivos: `spec/services/scan_solo/knowledge/ingestion_service_spec.rb`
      Mudança: acrescentar `# rubocop:disable Rails/SkipsModelValidations` ao final da linha 39 (`update_columns` do teste CRLF), como nas linhas 81/90/100.
      Cobre: RF-20
      Depende de: nenhuma
      Acceptance criteria: `bundle exec rubocop spec/services/scan_solo/knowledge/ingestion_service_spec.rb` reporta 0 offenses; o spec continua verde.
      Testes: `spec/services/scan_solo/knowledge/ingestion_service_spec.rb` — suíte existente + rubocop.
- [ ] T09 — `PromptBuilder`: regras fixas de continuidade + instrução de registro
      Arquivos: `app/services/scan_solo/ai_turn/prompt_builder.rb`, `spec/services/scan_solo/ai_turn/prompt_builder_spec.rb`
      Mudança: constante congelada `CONTINUITY_RULES` com as 3 frases verbatim do RF-17 em uma seção `Regras fixas de atendimento` como primeira entrada de `rule_sections` (antes de `Regras do agente`), não lida da config; `ACTION_DESCRIPTIONS['qualification_field']` instrui registrar todos os dados de qualificação informados na mensagem do cliente numa única chamada com todos os campos.
      Cobre: RF-17, RF-18, RNF-06
      Depende de: nenhuma
      Acceptance criteria: system message contém verbatim "Nunca pergunte novamente informação já presente no contato, nos campos coletados ou no histórico.", "Responda primeiro à pergunta/intenção atual do cliente; só depois peça no máximo um campo faltante." e "Cumprimente apenas na primeira resposta da conversa; não repita saudação depois." com índice menor que `## Regras do agente`; mudar campos da config não as altera; instrução de registro presente sse `qualification_field` ofertada.
      Testes: `spec/services/scan_solo/ai_turn/prompt_builder_spec.rb` — 3 regras + ordem, imutáveis pela config, instrução de registro condicionada à oferta.

## Phase 2: Migração dos 6 consumidores para o resolvedor

Antes de implementar, leia:
1. `.spec/features/scansolo-agent-qualification-continuity/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-agent-qualification-continuity/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-agent-qualification-continuity/asyncapi.yaml` — contrato CT-05 refinado (T07)

- [ ] T03 — `ContextAssembler#pipeline_context` via resolvedor
      Arquivos: `app/services/scan_solo/ai_turn/context_assembler.rb`, `spec/services/scan_solo/ai_turn/context_assembler_spec.rb`
      Mudança: `collected_fields = FieldResolver.call(contact: opportunity.contact, config: config).collected` e `missing_fields = ...missing_labels` (config já carregado); remover `slice`/`attributes[field].blank?`; atualizar comentário; `RECENT_MESSAGE_LIMIT` inalterado.
      Cobre: RF-07, RF-08, RNF-06
      Depende de: T01
      Acceptance criteria: `name`/`email` nativos + config com `"Nome"`/`"E-mail"` → nenhum em `missing_fields` e ambos em `collected_fields` com valores nativos; `{"cidade_uf"=>"Rio/RJ"}` com rótulo `"Cidade / UF"` → fora de `missing_fields`; arquivo sem `required_qualification_fields`.
      Testes: `spec/services/scan_solo/ai_turn/context_assembler_spec.rb` — nativos satisfazem; dado sob chave alternativa reconhecido.
- [ ] T04 — `QualificationFieldAction`: aliases, captura múltipla, nativos sem sobrescrita, evidência
      Arquivos: `app/services/scan_solo/actions/qualification_field_action.rb`, `spec/services/scan_solo/actions/qualification_field_action_spec.rb`
      Mudança: cada chave → `FieldResolver.canonical_key`; nativa (`nome/email/telefone`, mesmo fora da lista) → escreve só se nativo em branco, senão `not_applied_fields` `native_already_present`; obrigatória publicada → `custom_attributes[canonical]` (sem reescrever/apagar chave existente); outra → `unrecognized_fields` verbatim, não persistida. `contact.valid?` antes da escrita: atributo nativo inválido é restaurado e reportado com motivo; um único `save!`. Transições via `StageTransitionService`: `em_contato → em_qualificacao` quando ≥1 chave aceita resolve para campo obrigatório; `em_qualificacao → qualificado` quando há campos obrigatórios e o resolvedor recalculado não tem faltantes. Retorno `{opportunity_id, contact_id, updated_fields, not_applied_fields: [{field, reason}], unrecognized_fields}`; `SCHEMA` inalterado; atualizar comentário.
      Cobre: RF-07, RF-09, RF-10, RF-11, RF-12, RF-21, CT-08, RNF-02, RNF-06
      Depende de: T01
      Acceptance criteria: config v2 + `"Nome"` e `{nome: "Leonardo", cidade_uf: "Rio/RJ", area: "800 m²", prazo_desejado: "amanhã"}` em contato sem nome → resolvedor reporta os 4 satisfeitos e exatamente 1 UPDATE em `contacts`; config v2 sem `"Nome"` + `{nome: "Leonardo"}` → `contact.name = "Leonardo"`, não listado como desconhecido, etapa inalterada; `name = "Milena (WhatsApp)"` + `{nome: "Milena Souza"}` → nome inalterado e listado como não aplicado; `{email: "invalido", cidade_uf: "Rio/RJ"}` → email em branco com motivo, `cidade_uf` salvo, 1 UPDATE, sem exceção; `cor_favorita` fora do contato e em `unrecognized_fields` do retorno e do `AuditEvent agent_action.qualification_field`; `{"Cidade / UF": "Macaé/RJ"}` grava `custom_attributes["cidade_uf"]` e mantém `"Cidade / UF"`; único faltante satisfeito por nativo → `qualificado` uma vez; faltante restante → etapa inalterada; arquivo sem `required_qualification_fields`.
      Testes: `spec/services/scan_solo/actions/qualification_field_action_spec.rb` — captura múltipla (UPDATE contado via `sql.active_record`), nativos RF-10, desconhecida na evidência/auditoria, transições RF-12 + gate de proposta inalterado, escrita canônica RF-21; exemplos `budget`/`timeline` existentes verdes.
- [ ] T05 — `ReplyCompletenessDetector` via resolvedor
      Arquivos: `app/services/scan_solo/cadence/reply_completeness_detector.rb`, `spec/services/scan_solo/cadence/reply_completeness_detector_spec.rb`
      Mudança: `missing_fields` = `FieldResolver.call(contact: opportunity.contact, config: AiAgentConfig.published_for(opportunity.account)).missing_labels`; remover `required_fields` e checagem exata; cancelamento inalterado; atualizar comentário.
      Cobre: RF-07, RF-13
      Depende de: T01
      Acceptance criteria: campos restantes satisfeitos só por nativo/alias → `complete? == true` e todas as tentativas agendadas canceladas; um insatisfeito → só a primeira agendada por enrollment ativo cancelada; arquivo sem `required_qualification_fields`.
      Testes: `spec/services/scan_solo/cadence/reply_completeness_detector_spec.rb` — completo via nativo/alias; parcial.
- [ ] T06 — `GenerateService` (gate de proposta) via resolvedor
      Arquivos: `app/services/scan_solo/proposal/generate_service.rb`, `spec/services/scan_solo/proposal/generate_service_spec.rb`
      Mudança: `missing_required_fields` = `FieldResolver...missing_labels`; mesma rejeição `ActiveRecord::RecordInvalid` com `campos obrigatórios da proposta incompletos: <labels>`; atualizar comentário.
      Cobre: RF-07, RF-14, RNF-04
      Depende de: T01
      Acceptance criteria: `email` nativo + `"E-mail"` obrigatório + demais por alias → versão criada; um insatisfeito → 422/RecordInvalid citando exatamente esse rótulo e 0 `ProposalVersion`; `spec/requests/api/v1/accounts/scan_solo/proposals_spec.rb` verde sem modificação; arquivo sem `required_qualification_fields`.
      Testes: `spec/services/scan_solo/proposal/generate_service_spec.rb` — sucesso via nativo/alias; rejeição com rótulo exato.
- [ ] T07 — `MakeProvider`: `qualification` canônico (CT-05)
      Arquivos: `app/services/scan_solo/proposal/make_provider.rb`, `spec/services/scan_solo/proposal/make_provider_spec.rb`
      Mudança: `qualification = FieldResolver.call(contact: opportunity.contact, config: config).make_qualification`; resto do payload inalterado; comentário aponta para o asyncapi desta feature; exemplos que esperavam `{ 'budget' => '5000' }` reescritos (comportamento substituído).
      Cobre: RF-07, RF-15, CT-05, RNF-04
      Depende de: T01
      Acceptance criteria: config v2 publicada com valores sob rótulos em português + `name`/`email` nativos → `qualification` só com chaves de `MAKE_KEYS`, todas `^[a-z0-9_]+$`, valores iguais aos gravados; config v2 sem `"Nome"`/`"Telefone"` + nativos → `nome` e `telefone` enviados; chave sem valor ausente (nenhum `nil`); `integracao_seguranca` nunca enviada; payload valida contra `asyncapi.yaml` `MakeIntegrationRequestPayload`.
      Testes: `spec/services/scan_solo/proposal/make_provider_spec.rb` — chaves canônicas com config v2, nativos fora da lista enviados, present-only.
- [ ] T08 — `HandoffService`: linha "Campos de qualificação coletados" via resolvedor
      Arquivos: `app/services/scan_solo/handoff/handoff_service.rb`, `spec/services/scan_solo/handoff/handoff_service_spec.rb`
      Mudança: `qualification_fields` usa `FieldResolver.call(contact:, config: published_for(conversation.account)).collected` → `"<rótulo>: <valor>"` na ordem da config, `nenhum` quando vazio/sem contato; outras 8 linhas inalteradas.
      Cobre: RF-07, RF-16
      Depende de: T01
      Acceptance criteria: `email` nativo + `{"cidade_uf"=>"Rio/RJ"}` + config v2 → linha contém `E-mail: <email>` e `Cidade / UF: Rio/RJ`; as outras 8 linhas iguais às de antes; arquivo sem `required_qualification_fields`.
      Testes: `spec/services/scan_solo/handoff/handoff_service_spec.rb` — linha via resolvedor; demais linhas inalteradas.

## Phase 3: Provas cruzadas e documentação

Antes de implementar, leia:
1. `.spec/features/scansolo-agent-qualification-continuity/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-agent-qualification-continuity/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-agent-qualification-continuity/asyncapi.yaml` — contrato CT-05 refinado (T12)

- [ ] T10 — Spec de consistência dos 6 consumidores + dados sob rótulos antigos
      Arquivos: `spec/services/scan_solo/qualification/consumer_consistency_spec.rb` (novo)
      Mudança: mesmo contato (nativos + custom sob chave canônica, rótulo e alias) e config v2 + `"Nome"`; derivar satisfeitos/faltantes de `ContextAssembler`, `ReplyCompletenessDetector`, `GenerateService`, `HandoffService`, `MakeProvider` (stub de `Make::OutboundRequestService`) e `QualificationFieldAction` (transição a `qualificado`) e comparar; asserção estática de que os 6 arquivos não contêm `required_qualification_fields` nem `custom_attributes[field]`.
      Cobre: RF-07, RNF-06
      Depende de: T03, T04, T05, T06, T07, T08
      Acceptance criteria: conjuntos de rótulos satisfeitos e faltantes idênticos entre os 6 consumidores para o mesmo contato/config; oportunidade com dados sob rótulos antigos/alternativos não aparece como faltante em nenhum; asserção estática verde.
      Testes: `spec/services/scan_solo/qualification/consumer_consistency_spec.rb` — consistência + alias legado + estático.
- [ ] T11 — Integração com mock LLM (continuidade ponta a ponta)
      Arquivos: `spec/integration/scan_solo/qualification_continuity_spec.rb` (novo)
      Mudança: turnos via `TurnOrchestrator.call(message:, llm_provider: ->(**kw) { ScanSolo::TestMode::MockLlmProvider.call(**kw, fixture_actions: [...]) })` com config publicada elegível (`allowed_inbox_ids`), asserindo em `MockLlmProvider.last_payload` e no que a ação fixture salvou; texto da resposta do mock não é assertado.
      Cobre: RF-17, RF-08, RF-11, RNF-06
      Depende de: T03, T04, T09
      Acceptance criteria: (a) 3 regras fixas no system do `last_payload`; (b) contato com `name` → "Campos faltantes" sem `Nome`; (c) pergunta técnica (tubo de PVC) presente no histórico do payload; resposta parcial → próximo payload lista só o restante; dados fora de ordem (`prazo_desejado`, `cidade_uf`, `area`) todos salvos; (d) após `HandoffService` + `ReturnToAiService`, nova mensagem → `missing_fields` exclui todos os já satisfeitos; chave desconhecida da fixture presente em `AiTurn#action_evidence` e no `GET /api/v1/accounts/:account_id/scan_solo/ai_turns/:correlation_id`.
      Testes: `spec/integration/scan_solo/qualification_continuity_spec.rb` — nome + pergunta técnica; resposta parcial; fora de ordem; retorno após handoff; evidência.
- [ ] T12 — Documentação e contrato base (sem drift do `/ai-context`)
      Arquivos: `docs/agents/domain_rules.md`, `.spec/features/scansolo-production-complete/asyncapi.yaml`
      Mudança: `domain_rules.md` "Reply completeness" e "Proposal lifecycle" citam `ScanSolo::Qualification::FieldResolver` no lugar de `contact.custom_attributes[field].present?`; `qualification.description` do asyncapi anterior vira "fixed canonical key set, present-only" com ponteiro para o asyncapi desta feature; nenhuma outra linha.
      Cobre: CT-05
      Depende de: T07
      Acceptance criteria: `grep -n "custom_attributes\[field\]" docs/agents/domain_rules.md` vazio; asyncapi anterior sem "Keys = the published config's"; `spec/lib/scansolo_*doc*_spec.rb` verdes.
      Testes: `spec/lib/scansolo_deployment_doc_spec.rb`, `spec/lib/scansolo_go_live_test_doc_spec.rb`, `spec/lib/scansolo_migration_design_doc_spec.rb` — continuam verdes.

## Phase 4: Gates de qualidade e regressão

Antes de implementar, leia:
1. `.spec/features/scansolo-agent-qualification-continuity/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-agent-qualification-continuity/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T13 — Gates de qualidade e regressão
      Arquivos: nenhum arquivo novo (verificação sobre os arquivos alterados em T01..T12)
      Mudança: rubocop em todos os `.rb` alterados; `./scripts/ralph-test.sh`; probes RNF-02/03/04; corrigir qualquer offense ou falha na task de origem.
      Cobre: RNF-02, RNF-03, RNF-04, RNF-05
      Depende de: T01, T02, T03, T04, T05, T06, T07, T08, T09, T10, T11, T12
      Acceptance criteria: `bundle exec rubocop` nos `.rb` alterados → 0 offenses; `./scripts/ralph-test.sh` → exit 0; `git diff --stat main -- db/` vazio; `grep -rnE "enterprise/|Captain::"` nos arquivos alterados vazio; `git diff main -- spec/requests` vazio.
      Testes: `./scripts/ralph-test.sh` — suíte ScanSolo Ruby + frontend completa.
