# Phases: scansolo-escalacao-comercial-wame

Gerado por /plan a partir de PLAN.md — view executável para `./ralph.sh .spec/features/scansolo-escalacao-comercial-wame/PHASES.md`.

Regras para todas as fases:
- Migrações só aditivas.
- Specs só em caminhos com `scan_solo`/`scansolo`.
- i18n só em `config/locales/en.yml` e `app/javascript/dashboard/i18n/locale/en/scansolo.json` (conteúdo pt-BR).
- Nenhum telefone real no Git: usar só o fictício `+5511999999999`.
- "Luciano" nunca em string de produto, prompt ou KB.
- Não rodar `annotaterb`.
- Camadas (`docs/agents/architecture.md`): controller valida o formato do request e devolve 422; service é dono de regra, transação e auditoria; job não decide elegibilidade.

## Phase 1: Schema, modelos e regras compartilhadas

Antes de implementar, leia:
1. `.spec/features/scansolo-escalacao-comercial-wame/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-escalacao-comercial-wame/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T01 — Additive migrations, schema and model support for the commercial number and the escalation mark
      Arquivos:
        - `db/migrate/20261109100001_add_commercial_whatsapp_number_to_scan_solo_ai_agent_configs.rb` (novo)
        - `db/migrate/20261109100002_add_commercial_escalation_to_scan_solo_pipeline_opportunities.rb` (novo)
        - `db/schema.rb`
        - `app/models/scan_solo/ai_agent_config.rb`
        - `app/models/scan_solo/pipeline_opportunity.rb`
        - `spec/db/scansolo_migrations_spec.rb`
        - `spec/models/scan_solo/pipeline_opportunity_escalation_spec.rb` (novo)
      Mudança:
        - Colunas nullable via `add_column`, sem default: `scan_solo_ai_agent_configs.commercial_whatsapp_number` (string), `scan_solo_pipeline_opportunities.escalated_to_commercial_at` (datetime) e `escalation_reason` (string).
        - `AiAgentConfig::FIELDS` inclui `commercial_whatsapp_number`.
        - `PipelineOpportunity`:
          - `ESCALATION_REASONS` com os 6 motivos;
          - validação de inclusão `allow_nil`;
          - `escalated_to_commercial?` = marca presente e etapa fora de `ganho`/`perdido`.
        - Anotação do schema no modelo editada à mão.
        - Contagem do `scansolo_migrations_spec`: 44 → 46.
      Cobre: RF-09, RF-11, RF-17, RF-01, RF-02, RNF-02
      Acceptance criteria:
        - As 2 migrações usam só `add_column` e as 3 colunas existem e são nullable no `db/schema.rb`.
        - `AiAgentConfig::FIELDS` contém `commercial_whatsapp_number`.
        - `PipelineOpportunity#escalated_to_commercial?`:
          - é true com marca em etapa não terminal;
          - é false sem marca;
          - é false em `ganho`/`perdido`.
        - `escalation_reason` fora dos 6 valores invalida o registro.
        - `scansolo_migrations_spec` espera 46.
      Testes:
        - `spec/db/scansolo_migrations_spec.rb`: contagem 46 e aditividade.
        - `spec/models/scan_solo/pipeline_opportunity_escalation_spec.rb`: predicado e validação.
- [ ] T02 — Shared commercial contact rules (E.164 and internal name)
      Arquivos:
        - `app/services/scan_solo/commercial/rules.rb` (novo)
        - `app/controllers/api/v1/accounts/scan_solo/pipeline_opportunities_controller.rb`
        - `spec/services/scan_solo/commercial/rules_spec.rb` (novo)
      Mudança:
        - `ScanSolo::Commercial::Rules` com:
          - `E164_PHONE_REGEXP`, movido do `PipelineOpportunitiesController`;
          - `INTERNAL_NAME_PATTERN = /luciano/i`;
          - `internal_name?(text)`, que usa `I18n.transliterate` para ignorar maiúsculas e acentos.
        - O controller passa a usar `Rules::E164_PHONE_REGEXP`, e a constante antiga é removida.
      Cobre: RF-01, RF-07, RF-08, RF-20, RF-22
      Acceptance criteria:
        - `Rules.internal_name?` é true para "luciano", "LUCIANO" e "Lucíano", e false para "Artur".
        - O E.164 aceita `+5511999999999` e rejeita `11999999999`.
        - `PipelineOpportunitiesController` não define mais `E164_PHONE_REGEXP`, e o create com telefone inválido continua devolvendo 422 `invalid_phone`.
      Testes:
        - `spec/services/scan_solo/commercial/rules_spec.rb`: casos do nome e do E.164.
        - `spec/requests/api/v1/accounts/scan_solo/pipeline_opportunities_create_spec.rb`: continua verde.

## Phase 2: Bordas de config e knowledge + campo no Agent Center

Antes de implementar, leia:
1. `.spec/features/scansolo-escalacao-comercial-wame/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-escalacao-comercial-wame/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-escalacao-comercial-wame/openapi.yaml` — contrato de draft, publish e knowledge/sources (CT-01, CT-06)

- [ ] T03 — Agent config API: commercial_whatsapp_number on draft/show/publish and publish 422 when enabled without number
      Arquivos:
        - `app/controllers/api/v1/accounts/scan_solo/ai_agent_configs_controller.rb`
        - `app/views/api/v1/accounts/scan_solo/ai_agent_configs/_ai_agent_config.json.jbuilder`
        - `spec/requests/api/v1/accounts/scan_solo/ai_agent_configs_spec.rb`
      Mudança:
        - `validate_commercial_params` aceita só `nil` ou String E.164 (`Rules::E164_PHONE_REGEXP`). Fora disso, `errors.add(:commercial_whatsapp_number)` e o `RecordInvalid` existente devolve 422.
        - Permitir o campo em `draft_params`.
        - Em `publish`, depois do `authorize`, se `@draft.enabled` e o número estiver vazio, levantar `RecordInvalid` antes do `PublishService`.
        - O jbuilder parcial expõe `commercial_whatsapp_number`.
      Cobre: RF-01, RF-21, RF-02, CT-01
      Acceptance criteria:
        - PUT draft com `"+5511999999999"` devolve 200 e grava o valor.
        - PUT draft com `"11999999999"`, `"+55 11 99999-9999"`, `5511999999999` (inteiro) ou `""` devolve 422, com `attributes` contendo `commercial_whatsapp_number` e o draft inalterado.
        - PUT draft com `null` devolve 200 e limpa o valor.
        - POST publish com `enabled: true` e sem número devolve 422, sem novo snapshot e sem audit `ai_agent_config.published`.
        - POST publish com `enabled: false` e sem número devolve 200.
        - POST publish com número devolve 200, e o snapshot carrega o número.
        - GET expõe o campo no draft e no published.
      Testes:
        - `spec/requests/api/v1/accounts/scan_solo/ai_agent_configs_spec.rb`: todos os casos acima.
- [ ] T04 — Knowledge "Luciano" guard: 422 on source writes and failed ingestion with chunk removal
      Arquivos:
        - `app/controllers/api/v1/accounts/scan_solo/knowledge/sources_controller.rb`
        - `app/services/scan_solo/knowledge/ingestion_service.rb`
        - `spec/requests/api/v1/accounts/scan_solo/knowledge/sources_spec.rb`
        - `spec/services/scan_solo/knowledge/ingestion_service_spec.rb`
        - `spec/jobs/scan_solo/knowledge_ingestion_job_spec.rb`
      Mudança:
        - Controller: `create` e `update` levantam `ActiveRecord::RecordInvalid` (422, mesmo corpo do controller) quando `Rules.internal_name?` casa com `title` ou `content`.
        - IngestionService: depois de marcar `indexing`, se o conteúdo casar, faz numa transação `knowledge_chunks.destroy_all` e `update!(index_status: :failed, index_error: INTERNAL_NAME_ERROR, chunk_count: 0)`, sem chamar embedding. O `INTERNAL_NAME_ERROR` é em pt-BR e não cita o nome.
        - `RetrievalService` fica inalterado.
      Cobre: RF-20, RF-22, CT-06, RF-08
      Acceptance criteria:
        - POST com content "fale com o Luciano" ou title "LUCIANO" devolve 422, sem criar fonte nem audit.
        - PATCH/PUT com o nome devolve 422 e a fonte fica inalterada.
        - As mesmas requisições sem o nome devolvem 2xx.
        - Ingerir uma fonte com "luciano" deixa:
          - `index_status = failed` e `index_error` presente;
          - 0 chamadas ao provedor de embedding;
          - 0 chunks da fonte, inclusive chunks de uma indexação anterior bem-sucedida;
          - 0 resultados dessa fonte no `RetrievalService`.
        - Fonte sem o nome continua terminando `indexed`.
      Testes:
        - `spec/requests/api/v1/accounts/scan_solo/knowledge/sources_spec.rb`: casos de 422 e de sucesso.
        - `spec/services/scan_solo/knowledge/ingestion_service_spec.rb`: falha, remoção de chunks e retrieval vazio.
        - `spec/jobs/scan_solo/knowledge_ingestion_job_spec.rb`: estado de falha propagado.
- [ ] T05 — Agent Center: commercial WhatsApp field (UI-01)
      Arquivos:
        - `app/javascript/dashboard/routes/dashboard/scansolo/agent/agentCenterFields.js`
        - `app/javascript/dashboard/routes/dashboard/scansolo/agent/AgentCenter.vue`
        - `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/pipelineConstants.js`
        - `app/javascript/dashboard/i18n/locale/en/scansolo.json`
        - `app/javascript/dashboard/routes/dashboard/scansolo/agent/specs/AgentCenter.spec.js`
      Mudança:
        - Campo `commercialWhatsappNumber` (FIELD_TYPES.PHONE) na seção `commercial`.
        - Erro inline computado com `E164_PHONE_PATTERN`; botão salvar desabilitado enquanto inválido.
        - O payload envia `commercial_whatsapp_number` com o valor aparado ou `null`.
        - Rótulo, erro e dica em pt-BR, citando Artur, sem dígitos e sem "Luciano".
        - Usar `<script setup>` e só Tailwind.
      Cobre: UI-01, CT-01, RNF-01, RNF-06
      Acceptance criteria:
        - Digitar `11999999999` mostra o erro inline e desabilita o salvar.
        - Salvar `+5511999999999` chama `updateDraft` com `commercial_whatsapp_number: '+5511999999999'`.
        - Campo vazio envia `null`.
        - Um 422 do servidor mostra o alerta de erro.
        - Draft vindo com `null` renderiza o input vazio.
        - Nenhuma string solta no template.
      Testes:
        - `app/javascript/dashboard/routes/dashboard/scansolo/agent/specs/AgentCenter.spec.js`: casos acima.

## Phase 3: Blocos de domínio

Antes de implementar, leia:
1. `.spec/features/scansolo-escalacao-comercial-wame/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-escalacao-comercial-wame/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-escalacao-comercial-wame/openapi.yaml` — `CommercialStatus` com `escalado_wa` (CT-04)

- [ ] T06 — escalate_to_commercial action, EscalationService, registry and per-turn offering
      Arquivos:
        - `app/services/scan_solo/commercial/escalation_service.rb` (novo)
        - `app/services/scan_solo/actions/escalate_to_commercial_action.rb` (novo)
        - `app/services/scan_solo/actions/registry.rb`
        - `app/services/scan_solo/ai_turn/input_guardrail.rb`
        - `spec/services/scan_solo/commercial/escalation_service_spec.rb` (novo)
        - `spec/services/scan_solo/actions/escalate_to_commercial_action_spec.rb` (novo)
        - `spec/services/scan_solo/actions/registry_spec.rb`
        - `spec/services/scan_solo/ai_turn/input_guardrail_spec.rb`
      Mudança:
        - `EscalationService.call(opportunity:, reason:, turn:)`, nesta ordem:
          1. `opportunity.lock!` (lock de linha até o commit do turno; turnos concorrentes serializam aqui);
          2. não faz nada se já existe um evento `commercial.escalated` com esse `correlation_id` para a oportunidade (1 escalação por turno);
          3. `first = !opportunity.escalated_to_commercial?`, lido depois do lock;
          4. grava `escalated_to_commercial_at = Time.current` e `escalation_reason`, sobrescrevendo os dois;
          5. registra o audit `commercial.escalated` com payload `{reason, conversation_id, message_id, stage}` e o `correlation_id` do turno;
          6. se `first`, agenda `ActiveRecord.after_all_transactions_commit` com `Notifications::Publisher.call(event: 'commercial.escalated', payload: NegotiationPayload.build(opportunity: opportunity.reload, trigger_message: turn.message, correlation_id: turn.correlation_id).merge(escalation_reason: reason))`; se não, 0 e-mails. A chave `escalation_reason` faz o T07 escolher o assunto por motivo; `NegotiationPayload` não muda, então o caminho de negociação sem número (T12) mantém "Pedido de negociação #…";
          7. devolve `{escalated: true, reason:, escalated_at:}`.
        - A ação (`automatic`, schema fechado do CT-02) chama o service. Ela não chama HandoffService nem StopRecalculatePolicy e não cria mensagem.
        - Registry ganha o handler. `HandoffAction` continua registrado só para trilha.
        - InputGuardrail:
          - `ALL_ACTIONS` inclui `escalate_to_commercial`;
          - `human_handoff` e `proposal_generate` nunca são oferecidos;
          - `escalate_to_commercial` só é oferecido quando `config.commercial_whatsapp_number` está presente.
      Cobre: RF-03, RF-04, RF-06, RF-09, RF-10, RF-11, RF-19, RF-23 (incl. `escalation_reason` no payload do aviso), CT-02, CT-03, RNF-05
      Acceptance criteria:
        - `scan_solo_agent_actions` tem `escalate_to_commercial` com classificação `automatic`.
        - Chave extra, `reason` ausente ou `reason` fora dos 6 valores levantam `InvalidParamsError`.
        - Repetir o mesmo `idempotency_key` gera 1 marca e 1 evento.
        - Segunda escalação em outro turno (`pedido_humano`) deixa o último motivo e horário nas colunas, com 2 eventos no total.
        - RF-23: para cada um dos 6 motivos, em oportunidade sem marca, depois do commit há 1 `Publisher.call` com o `correlation_id` do turno (1 `negotiation.notification_sent` com o adapter stubado).
        - Para cada um dos 6 motivos, o payload passado ao `Publisher.call` tem `escalation_reason` igual ao motivo e, fora isso, as mesmas chaves de `NegotiationPayload.build`.
        - Oportunidade já escalada (marca presente, etapa `negociacao`) escalada por outro `correlation_id`: 1 evento novo, colunas sobrescritas, 0 `Publisher.call`.
        - Marca presente mas etapa `ganho`: conta como primeira, 1 `Publisher.call`.
        - Objeto em memória sem marca e linha no banco já marcada (`update_columns` via outro `find`): 0 `Publisher.call` (decisão tomada depois do `lock!`).
        - Transação externa revertida: 0 `Publisher.call`, 0 eventos e colunas inalteradas.
        - A ação faz 0 chamadas a StopRecalculatePolicy, cria 0 mensagens, e `ai_control_state` continua `ai_active`.
        - Com número publicado, `allowed_actions` inclui `escalate_to_commercial` e não inclui `human_handoff`.
        - Sem número, `allowed_actions` não inclui nenhum dos dois.
      Testes:
        - `spec/services/scan_solo/actions/escalate_to_commercial_action_spec.rb`
        - `spec/services/scan_solo/commercial/escalation_service_spec.rb`
        - `spec/services/scan_solo/actions/registry_spec.rb`
        - `spec/services/scan_solo/ai_turn/input_guardrail_spec.rb`
- [ ] T07 — wa.me link builder, per-reason notice e-mail subjects and backend pt-BR strings
      Arquivos:
        - `app/services/scan_solo/commercial/whatsapp_link.rb` (novo)
        - `app/services/scan_solo/quote/email_composer.rb`
        - `config/locales/en.yml`
        - `spec/services/scan_solo/commercial/whatsapp_link_spec.rb` (novo)
        - `spec/services/scan_solo/quote/email_composer_spec.rb`
      Mudança:
        - `WhatsappLink::PLACEHOLDER = '{{LINK_ARTUR}}'`.
        - `build(config:, opportunity:)` devolve `nil` sem número. Com número, devolve `https://wa.me/<dígitos>?text=<ERB::Util.url_encode(texto)>`.
        - O texto vem de `scan_solo.commercial.whatsapp_text.*`: saudação ao Artur mais nome, empresa, serviço e número da proposta, cada um só quando conhecido. Empresa e serviço seguem a regra de status do jbuilder da oportunidade.
        - Assunto por motivo (decisão do desenvolvedor, antiga Q7): `EmailComposer.negotiation` usa `t("commercial.escalation_email.subjects.#{payload[:escalation_reason]}", opportunity_id:, name:)` quando o payload traz `escalation_reason` (T06), com `I18n.t` `raise: true`; sem a chave (negociação sem número, T12), mantém `negotiation.email.subject` = "Pedido de negociação #%{opportunity_id} — %{name}". Corpo, rótulos e `EmailAdapter` não mudam.
        - Novas chaves pt-BR `scan_solo.commercial.escalation_email.subjects.{duvida_sem_resposta,sem_informacao_base,negociacao,duvida_proposta,assunto_orcamento,pedido_humano}`, todas distintas entre si e de `negotiation.email.subject`, com `#%{opportunity_id}` e `%{name}`, citando o comercial só como "Artur" quando houver nome (redação sugerida no PLAN).
        - Nova chave `scan_solo.negotiation.escalation_reply` com `%{link}` e `%{email}`, sem valor, prazo ou `R$`.
        - `standard_reply` e `negotiation.email.subject` ficam inalterados.
      Cobre: RF-05, RF-15, RF-19, RF-20, RF-23, CT-05, RNF-01, RNF-04, RNF-06
      Acceptance criteria:
        - Com `+5511999999999`, a URL começa com `https://wa.me/5511999999999?text=`.
        - O texto decodificado contém "Artur", nome, empresa, serviço e `SS-2026-000123` quando todos são conhecidos.
        - Sem proposta, o texto não tem referência a proposta. Com `empresa` `nao_informado`, não tem linha de empresa.
        - Sem número, devolve `nil`.
        - Para cada um dos 6 motivos, `EmailComposer.negotiation(payload: payload.merge(escalation_reason: motivo))` devolve o assunto da chave `scan_solo.commercial.escalation_email.subjects.<motivo>`, contendo `#42`.
        - Os 6 assuntos são distintos entre si e nenhum é igual a "Pedido de negociação #42 — Solar Ltda".
        - Nenhum assunto (6 renderizados e 6 valores crus do en.yml) casa com `/luciano/i`.
        - Sem `escalation_reason`, o assunto continua exatamente "Pedido de negociação #42 — Solar Ltda", e o corpo é idêntico com e sem a chave.
        - O escopo `scan_solo` do en.yml não contém "luciano" nem telefone.
      Testes:
        - `spec/services/scan_solo/commercial/whatsapp_link_spec.rb`: casos do link acima.
        - `spec/services/scan_solo/quote/email_composer_spec.rb`: bloco `.negotiation` com os casos de assunto por motivo, distinção, `/luciano/i` e caminho sem motivo.
- [ ] T08 — Cadence hold: commercial_escalated defer in AttemptPrecheck, and mark cleared on ganho/perdido
      Arquivos:
        - `app/services/scan_solo/cadence/attempt_precheck.rb`
        - `app/services/scan_solo/pipeline/stage_transition_service.rb`
        - `spec/services/scan_solo/cadence/attempt_precheck_spec.rb`
        - `spec/jobs/scan_solo/cadence_due_attempt_job_spec.rb`
        - `spec/services/scan_solo/pipeline/stage_transition_service_spec.rb`
      Mudança:
        - Passo 3c, logo depois de `human_controlled`: `return defer('commercial_escalated') if opportunity.escalated_to_commercial?`.
        - Não altera o status da matrícula e não chama StopRecalculatePolicy.
        - Vale também para follow-ups de proposta enviada depois da escalação, até `ganho`/`perdido`.
        - Atualizar o comentário de ordem.
        - `StageTransitionService#call`: com `target_stage` em `TERMINAL_STAGES`, o `update!` existente passa a gravar também `escalated_to_commercial_at: nil` e `escalation_reason: nil`, na mesma transação do `PipelineStageEvent`. Eventos `commercial.escalated` ficam como histórico. Transições não terminais não mexem na marca.
      Cobre: RF-11, RF-23
      Acceptance criteria:
        - Oportunidade escalada em etapa não terminal: o precheck devolve `defer` com `commercial_escalated`.
        - Em `ganho`/`perdido` ou sem marca, não há defer por esse motivo.
        - `CadenceDueAttemptJob`, rodado depois do `scheduled_at` dentro da janela, envia 0 mensagens, a matrícula continua `active` e a tentativa continua `scheduled` com `last_block_reason = commercial_escalated`.
        - Uma matrícula criada depois da escalação também envia 0.
        - Oportunidade escalada cuja proposta é enviada depois da escalação (versão `sent`, etapa `proposta_enviada`) envia 0 follow-ups de proposta.
        - Oportunidade escalada movida para `ganho` ou `perdido` fica com `escalated_to_commercial_at` e `escalation_reason` nulos e mantém os eventos `commercial.escalated`; movida para `negociacao`, mantém a marca.
        - A escalação faz 0 chamadas a StopRecalculatePolicy com trigger `handoff`.
      Testes:
        - `spec/services/scan_solo/cadence/attempt_precheck_spec.rb`
        - `spec/jobs/scan_solo/cadence_due_attempt_job_spec.rb`
        - `spec/services/scan_solo/pipeline/stage_transition_service_spec.rb`
- [ ] T09 — OutputValidator: unpublished contact and internal name violations
      Arquivos:
        - `app/services/scan_solo/ai_turn/output_validator.rb`
        - `spec/services/scan_solo/ai_turn/output_validator_spec.rb`
      Mudança:
        - Novos kwargs `commercial_link:` e `allowed_phone_numbers:`.
        - Depois de `restricted_information`, nesta ordem:
          1. `:internal_name` quando `Rules.internal_name?(content)`;
          2. `:unpublished_contact` quando, removido o `commercial_link`, ainda sobrar `wa.me/` ou `api.whatsapp.com`, ou houver telefone (E.164 ou BR com DDD, com ou sem separadores) cujos dígitos normalizados (prefixo 55 em números de 10–11 dígitos) não estão na lista permitida.
        - Lookarounds excluem CNPJ, CPF, CEP, valores, datas e `SS-AAAA-NNNNNN`.
        - Os dois símbolos entram em `REGENERABLE_VIOLATIONS`.
        - A classe continua pura.
      Cobre: RF-07, RF-08, RNF-04
      Acceptance criteria:
        - Bloqueiam como `unpublished_contact`:
          - `https://wa.me/5511000000000`;
          - `api.whatsapp.com/send?phone=...`;
          - "(11) 98888-7777" com o número publicado `+5511999999999`.
        - Não bloqueiam:
          - conteúdo cujo único link é o `commercial_link`;
          - o número publicado escrito como "(11) 99999-9999";
          - um telefone da lista permitida.
        - CNPJ, CPF, CEP, `SS-2026-000123` e "09/11/2026" não viram `unpublished_contact`.
        - "fale com o Luciano" bloqueia como `internal_name`.
        - Os 2 símbolos estão em `REGENERABLE_VIOLATIONS`.
      Testes:
        - `spec/services/scan_solo/ai_turn/output_validator_spec.rb`: tabela positiva e negativa.
- [ ] T10 — CommercialStatus gains escalado_wa
      Arquivos:
        - `app/services/scan_solo/reports/commercial_status.rb`
        - `app/services/scan_solo/reports/report_builder.rb`
        - `app/views/api/v1/accounts/scan_solo/pipeline_opportunities/_pipeline_opportunity.json.jbuilder`
        - `spec/services/scan_solo/reports/commercial_status_spec.rb`
        - `spec/services/scan_solo/reports/report_builder_spec.rb`
        - `spec/requests/api/v1/accounts/scan_solo/pipeline_opportunities_spec.rb`
      Mudança:
        - `VALUES` ganha `escalado_wa` (7 valores).
        - `call(quote_request:, current_version:, escalated:)`, com keyword obrigatória.
        - Ordem: `proposta_enviada_manual` → `proposta_enviada` → `proposta_em_aprovacao` → `escalado_wa` → linhas existentes.
        - Os 2 chamadores passam `escalated: opportunity.escalated_to_commercial?`.
        - `StallReason` fica inalterado.
      Cobre: RF-17, CT-04
      Acceptance criteria:
        - Escalado sem pedido, com pedido aberto ou com pedido respondido devolve `escalado_wa`.
        - Escalado com `handled_manually` devolve `proposta_enviada_manual`.
        - Escalado com versão `sent` devolve `proposta_enviada`.
        - Escalado com `awaiting_approval` devolve `proposta_em_aprovacao`.
        - Não escalado (sem marca, ou em `ganho`/`perdido`) nunca devolve `escalado_wa`, e a tabela antiga fica igual.
        - O JSON da oportunidade escalada traz `commercial_status: "escalado_wa"`.
        - O exemplo "never escalado_wa" foi substituído.
      Testes:
        - `spec/services/scan_solo/reports/commercial_status_spec.rb`
        - `spec/services/scan_solo/reports/report_builder_spec.rb`
        - `spec/requests/api/v1/accounts/scan_solo/pipeline_opportunities_spec.rb`

## Phase 4: Regras do prompt e serviço de negociação

Antes de implementar, leia:
1. `.spec/features/scansolo-escalacao-comercial-wame/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-escalacao-comercial-wame/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T11 — PromptBuilder fixed escalation rules (replace HANDOFF_RULE)
      Arquivos:
        - `app/services/scan_solo/ai_turn/prompt_builder.rb`
        - `spec/services/scan_solo/ai_turn/prompt_builder_spec.rb`
      Mudança:
        - Remover `HANDOFF_RULE` e a descrição de `human_handoff`.
        - `COMMERCIAL_GUARD_RULES` (sempre presentes): nunca negociar valor, prazo, desconto, pagamento ou condição, e nunca inventar resposta fora da base.
        - `ESCALATION_RULES`, só quando o número publicado está presente:
          - os 4 gatilhos em ordem, com seus motivos;
          - o contato é "Artur";
          - o link vai só como placeholder `WhatsappLink::PLACEHOLDER`, nunca URL ou telefone;
          - continuar respondendo depois de escalar;
          - manter o texto de transparência sobre o especialista virtual.
        - Descrição da ação `escalate_to_commercial` em `ACTION_DESCRIPTIONS`.
        - `VIOLATION_INSTRUCTIONS` ganha `unpublished_contact` e `internal_name`.
      Cobre: RF-04, RF-08, RF-12, RF-16, RF-19
      Acceptance criteria:
        - Com número publicado e campos livres vazios, a system message contém os 4 gatilhos com os ids dos motivos, "Artur", o placeholder, a regra de nunca negociar e a de nunca inventar.
        - O mesmo vale quando `instructions` contradiz essas regras.
        - A mensagem tem 0 `human_handoff` e 0 `/luciano/i`.
        - Sem número, não há placeholder nem regra de escalação, mas nunca negociar e nunca inventar continuam presentes.
        - `correction_block` funciona para as 2 novas violações.
      Testes:
        - `spec/services/scan_solo/ai_turn/prompt_builder_spec.rb`: casos acima, com os exemplos de HANDOFF_RULE reescritos.
- [ ] T12 — Negotiation::RequestService: escalate instead of handoff/assignment
      Arquivos:
        - `app/services/scan_solo/negotiation/request_service.rb`
        - `spec/services/scan_solo/negotiation/request_service_spec.rb`
      Mudança:
        - Nova assinatura `call(opportunity:, turn:, message:, escalation_reason:)`, com `escalation_reason` em `negociacao`, `duvida_proposta` ou `nil`.
        - Mantém:
          - a transição `proposta_enviada → negociacao`, sem mudar a etapa em `qualificado` ou `negociacao`;
          - o audit `negotiation.requested`, agora com `escalation_reason` no payload;
          - o Publisher depois do commit, agora só quando `escalation_reason` é `nil` (sem número publicado, e-mail como hoje).
        - Com `escalation_reason`, o service não publica: o `EscalationService` publica só na 1ª escalação.
        - Remove HandoffService, StopRecalculatePolicy('handoff'), `HANDOFF_REASON`, `assign_commercial_user` e o audit `negotiation.assignment_failed`.
        - Com `escalation_reason`, chama `Commercial::EscalationService` na mesma transação, depois da transição de etapa.
      Cobre: RF-13, RF-14, RF-19, RF-23
      Acceptance criteria:
        - Em `proposta_enviada`, sem escalação anterior:
          - a etapa vai para `negociacao`, com 1 PipelineStageEvent;
          - 1 marca `negociacao`;
          - 1 `negotiation.requested` e, depois do commit, 1 `negotiation.notification_sent`;
          - `ai_active`, `assignee_id` inalterado, 0 notas privadas e 0 StopRecalculatePolicy.
        - Já escalada (marca presente, etapa `negociacao`): marca sobrescrita, 1 `commercial.escalated` novo, 0 `negotiation.notification_sent` novos, 0 e-mails.
        - Em `qualificado` com `duvida_proposta`, sem escalação anterior: etapa inalterada, 0 stage events, 1 marca, 1 `negotiation.requested` e 1 `negotiation.notification_sent`; já escalada: 1 `commercial.escalated` novo e 0 `negotiation.notification_sent` novos.
        - Com `escalation_reason: nil`: sem marca, e o e-mail é publicado 1 vez (como hoje).
      Testes:
        - `spec/services/scan_solo/negotiation/request_service_spec.rb`: casos acima, com os exemplos de handoff e atribuição reescritos.

## Phase 5: Integração no turno

Antes de implementar, leia:
1. `.spec/features/scansolo-escalacao-comercial-wame/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-escalacao-comercial-wame/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T13 — AttemptRunner wiring: commercial requests, link resolution and validator inputs
      Arquivos:
        - `app/services/scan_solo/ai_turn/attempt_runner.rb`
        - `spec/services/scan_solo/ai_turn/attempt_runner_spec.rb`
      Mudança:
        - `NEGOTIATION_STAGES = %w[qualificado proposta_enviada negociacao]`.
        - `handle_commercial_request!` substitui o fluxo antigo de negociação:
          - motivo `negociacao` quando há `negotiation_requested` ou escalate com reason `negociacao`;
          - motivo `duvida_proposta` quando há escalate com reason `duvida_proposta` em `qualificado`;
          - em `NEGOTIATION_STAGES`, chama RequestService com `escalation_reason` (ou `nil` sem número publicado);
          - `duvida_proposta` (ou outro motivo) em `proposta_enviada`/`negociacao` não roda RequestService: a ação já escalou e o `EscalationService` manda o e-mail na 1ª escalação;
          - `negociacao` com número publicado troca a resposta por `escalation_reply` (placeholder + `config.quote_recipient_email`) e garante a escalação;
          - sem número, quando o RequestService rodou, usa `standard_reply`.
        - Depois, `resolve_commercial_link!`:
          - com link, troca o 1º placeholder pelo link e remove os demais;
          - se houve escalação nesta tentativa e não havia placeholder, anexa o link;
          - sem número, remove todo placeholder.
        - `validate_reply` passa `commercial_link` e `allowed_phone_numbers` (número publicado, telefone do contato e campo `telefone`).
        - 1 único ResponseSender; 0 novas chamadas de LLM ou HTTP.
      Cobre: RF-02, RF-05, RF-06, RF-07, RF-13, RF-14, RF-15, RF-19, RF-23, RNF-04
      Acceptance criteria:
        - Turno com `escalate_to_commercial` envia 1 mensagem outgoing `scansolo_origin: 'ai'` com o link exatamente 1 vez, com ou sem o placeholder na resposta do modelo.
        - Com draft A e publicado B, o link contém só B.
        - Negociação em `qualificado` mantém a etapa, grava 1 marca, e a resposta contém `https://wa.me/` e o `quote_recipient_email` publicado (`vendas@example.com`), não `comercial@scansolo.com.br`.
        - Em `proposta_enviada`, a etapa vai para `negociacao`.
        - Sem número publicado, a resposta é igual ao `standard_reply`, com 0 `wa.me` e 0 `{{`, e o turno não fica failed.
        - Resposta bloqueada desfaz a marca e o audit e publica 0 e-mails.
        - `negotiation_requested` em oportunidade já escalada: 0 `Publisher.call`, e a resposta ainda traz `wa.me` e o e-mail publicado.
        - A escalation_reply passa no check de `price`.
      Testes:
        - `spec/services/scan_solo/ai_turn/attempt_runner_spec.rb`: casos acima, com os exemplos antigos que esperavam `awaiting_human` reescritos.

## Phase 6: Spec de integração e rótulos do front

Antes de implementar, leia:
1. `.spec/features/scansolo-escalacao-comercial-wame/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-escalacao-comercial-wame/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-escalacao-comercial-wame/openapi.yaml` — `CommercialStatus` com `escalado_wa` (CT-04)

- [ ] T14 — End-to-end integration spec with mocked LLM
      Arquivos:
        - `spec/integration/scan_solo/escalacao_comercial_wame_spec.rb` (novo)
      Mudança:
        - Um arquivo de integração com config publicada com `+5511999999999`, LLM mockado e WebMock, seguindo `lead_state_turn_spec.rb` e `spec/support/scansolo_test_mode.rb`.
        - Exemplos (a)–(k) e (c2) do PLAN T14.
      Cobre: RF-06, RF-07, RF-08, RF-10, RF-11, RF-12, RF-13, RF-14, RF-15, RF-18, RF-19, RF-23, RNF-04
      Acceptance criteria:
        - Os 4 gatilhos (`duvida_proposta` em qualificado, `assunto_orcamento`, `duvida_sem_resposta`, `pedido_humano`) terminam cada um, em oportunidade não escalada antes, com 1 resposta com link, 1 marca com o motivo esperado, `ai_active` e 1 e-mail de aviso ao comercial (`negotiation.notification_sent` com o `correlation_id` do turno).
        - Depois de escalar, nova dúvida respondível pela KB recebe 1 resposta da IA, com 0 notas de handoff.
        - Negociação em `proposta_enviada` e em `qualificado` segue RF-13 e RF-14.
        - `duvida_proposta` em `proposta_enviada` sem escalação anterior manda 1 e-mail; um turno seguinte com `pedido_humano` gera 1 `commercial.escalated` novo e 0 `negotiation.notification_sent` novos.
        - Segunda negociação volta a trazer `wa.me` e o e-mail publicado, e manda 0 e-mails de aviso novos.
        - `wa.me` não publicado regenera 1 vez, e o fallback não traz número não publicado.
        - "Luciano" é bloqueado.
        - Resposta humana a um lead escalado leva a `human_active` e 0 respostas da IA depois.
        - Snapshot sem número não oferece a ação e usa `standard_reply`.
        - Tentativa vencida de um lead escalado fica adiada, inclusive o follow-up de proposta enviada depois da escalação; depois de `ganho`, a marca fica limpa.
        - 1 chamada de LLM por tentativa aprovada.
      Testes:
        - `spec/integration/scan_solo/escalacao_comercial_wame_spec.rb`: exemplos (a)–(k) e (c2).
- [ ] T15 — Frontend labels for escalado_wa, the new defer reason and the new action
      Arquivos:
        - `app/javascript/dashboard/routes/dashboard/scansolo/scansoloLabels.js`
        - `app/javascript/dashboard/i18n/locale/en/scansolo.json`
        - `app/javascript/dashboard/routes/dashboard/scansolo/specs/i18nCompleteness.spec.js`
        - `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/specs/KanbanBoard.spec.js`
        - `app/javascript/dashboard/routes/dashboard/scansolo/pipeline/specs/OpportunityDetail.spec.js`
        - `app/javascript/dashboard/routes/dashboard/scansolo/reports/specs/Reports.spec.js`
      Mudança:
        - `COMMERCIAL_STATUS_LABELS.escalado_wa` → `SCANSOLO.COMMERCIAL_STATUS.ESCALADO_WA` ("Encaminhado ao Artur (WhatsApp)").
        - `REASON_LABELS.commercial_escalated` e `AI_ACTION_LABELS.escalate_to_commercial`, com textos pt-BR citando Artur.
        - Nenhuma mudança em Vue: os 4 lugares já usam `enumLabel` com esse mapa.
      Cobre: UI-02, RNF-06
      Acceptance criteria:
        - `COMMERCIAL_STATUS_LABELS` tem 7 chaves, e todas resolvem.
        - Card, detalhe e tabela de parados mostram o rótulo com "Artur" para `commercialStatus: 'escalado_wa'`.
        - O filtro do Kanban tem 1 opção `escalado_wa`, e selecioná-la mostra só esses cards.
        - A asserção `/luciano/i` do `i18nCompleteness.spec.js` continua verde.
      Testes:
        - `i18nCompleteness.spec.js`
        - `KanbanBoard.spec.js`
        - `OpportunityDetail.spec.js`
        - `Reports.spec.js`

## Phase 7: Varredura de regressão

Antes de implementar, leia:
1. `.spec/features/scansolo-escalacao-comercial-wame/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-escalacao-comercial-wame/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T16 — Regression sweep, RNF guards and full ScanSolo suite
      Arquivos:
        - `spec/integration/scan_solo/operacao_centralizada_spec.rb`
        - `spec/services/scan_solo/ai_turn/turn_orchestrator_actions_spec.rb`
        - `spec/services/scan_solo/ai_turn/model_invoker_spec.rb`
        - `spec/services/scan_solo/executions_feed_query_spec.rb`
        - `spec/lib/scansolo_locale_spec.rb`
        - `spec/lib/scansolo_no_phone_in_git_spec.rb` (novo)
      Mudança:
        - Ajustar só as expectativas presas ao comportamento removido: negociação levando a `awaiting_human` e atribuição, e `human_handoff` oferecido.
        - Os specs de takeover (`conversation_listener_spec.rb`, `spec/services/scan_solo/handoff/`, `implicit_takeover_spec.rb`) ficam intocados e verdes.
        - `scansolo_locale_spec` ganha a asserção de 0 `/luciano/i` no escopo `scan_solo` do en.yml.
        - Novo spec RNF-01: varre os arquivos da feature em busca de telefone, permitindo só o fictício.
        - Rodar `./scripts/ralph-test.sh`, `pnpm eslint` nos JS tocados e `bundle exec rubocop --force-exclusion` nos Ruby tocados.
      Cobre: RF-08, RF-18, RNF-01, RNF-03
      Acceptance criteria:
        - `./scripts/ralph-test.sh` sai com 0.
        - `scansolo_migrations_spec` (46) e o check de cron do `proposta_aprovacao_email_spec` estão verdes sem mudança no cron.
        - Os specs de takeover passam sem alteração.
        - O escopo `scan_solo` do en.yml tem 0 "luciano".
        - Nenhum telefone real nos arquivos da feature.
        - Rubocop e eslint limpos nos arquivos tocados.
      Testes:
        - `spec/lib/scansolo_locale_spec.rb`
        - `spec/lib/scansolo_no_phone_in_git_spec.rb`
        - suíte completa via `./scripts/ralph-test.sh`
