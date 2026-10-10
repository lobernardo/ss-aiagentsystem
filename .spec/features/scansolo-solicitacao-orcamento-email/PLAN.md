# Implementation Plan

## Request Summary
- Objective: trocar o assunto e o corpo do e-mail de solicitação de orçamento ao comercial (OC/CT-03) pelo modelo aprovado (CT-01), montado de forma determinística no Rails. Entram: assunto curto e pesquisável (`Solicitação de orçamento | {empresa_curta} | {servico_label}[ | {cidade}/{uf}]`), seções com omissão de campos vazios, telefone só do contato, pendências por tipo de serviço (CT-07), localização deduplicada, anexos do lead até 15 MB, parágrafo de modo validação controlado por uma flag nova da config publicada (com toggle na tela existente), e-mail de atualização mínimo no mesmo thread (janela fixa de 10 min, só antes da resposta processada), retry 1/5/15 min antes de a mensagem existir, nota privada + auditoria em falha, e auditoria com `template_version`. O bloco OC/CT-04, o `ResponseBlockParser` e o `ReplyProcessor` não mudam.
- Scope in: RF-01..RF-21, UI-01, CT-01..CT-07, RNF-01..RNF-08.
- Scope out: geração de PDF/template de proposta (feature futura `scansolo-proposta-template-local`), Make, Gotenberg; mudanças no bloco OC/CT-04, no parser, no `ReplyProcessor` e no e-mail de correção; gatilho da solicitação, aviso ao cliente (OC/RF-53) e contrato HTTP do reenvio (OC/CT-12); Reply-To novo; LLM, Receita, Google ou qualquer HTTP na montagem.
- Tier: standard
- SPEC: v1.2 (0 marcadores). Feature alterada: `.spec/features/scansolo-operacao-centralizada/` (OC, SPEC v1.3).
- Architecture references: `AGENTS.md` (= `CLAUDE.md`), `docs/agents/architecture.md`, `docs/agents/domain_rules.md`, `docs/agents/coding_guidelines.md`, `docs/agents/data_model.md` (consultado também `docs/agents/api_contracts.md`). Contratos base: `.spec/features/scansolo-operacao-centralizada/openapi.yaml` (v1.7.0) e `asyncapi.yaml` (v1.5.0).

### Regras de arquitetura preservadas (valem para todas as tasks)
- Base de comparação da feature: o commit `docs(spec)` que adiciona este plano (último commit só de `.spec/` antes do 1º commit de código). Até ele existir, `832721a15c`. Todo `git diff <base>` das tasks usa esse commit.
- `docs/agents/architecture.md` "Layer responsibilities":
  - Services (`services/scan_solo/*`): toda escrita e regra, 1 service por transição. `Quote::RequestService` continua o único caminho de envio da solicitação (verified at `app/services/scan_solo/quote/request_service.rb:43`); `Quote::UpdateService` (novo) é o único caminho do e-mail de atualização; `Quote::DeliveryFailureService` (novo) é o único caminho da nota privada + `quote_request.delivery_failed`.
  - Jobs (`jobs/scan_solo/*`): fronteira assíncrona, retry e espera (`QuoteRequestJob`, `QuoteRequestUpdateJob`).
  - Models: associações, enums, validações e invariantes de índice único (`scan_solo_quote_request_updates`, índice único `(quote_request_id, version_digest)`).
  - `ConversationListener`: só classifica e delega (T15 e T17 só acrescentam origens e uma delegação ao agendador).
  - Montagem do e-mail: objetos puros (`ScanSolo::Quote::RequestEmail` e colaboradores), sem escrita, sem HTTP e sem LLM (RF-01, RNF-01). A leitura do banco fica concentrada no `RequestEmail::Snapshot` (T11).
- `docs/agents/domain_rules.md` "Quote request and reply": inbox e destinatário vêm do `Quote::Mailbox` publicado; e-mail só depois do commit com auditoria `quote_request.sent`; `ResponseBlockParser` determinístico e intocado (RF-11). Regras de config: `PublishService` copia `AiAgentConfig::FIELDS` para o snapshot publicado (verified at `app/services/scan_solo/ai_agent/publish_service.rb:34`), então a flag nova entra em `FIELDS` (RF-21).
- Precedência de valor (`docs/agents/domain_rules.md`): lead state não `faltante` → coluna nativa → `custom_attributes` (verified at `app/services/scan_solo/qualification/field_resolver.rb:102`), exceto o telefone, que vem só de `contact.phone_number` (RF-07).
- RNF-04 (OC/RNF-01): e-mail e nota privada só fora de transação aberta. `Quote::EmailThread.post!` já levanta `CustomExceptions::ScanSolo::DeliveryInsideTransaction` (verified at `app/services/scan_solo/quote/email_thread.rb:29`); agendamentos a partir de escrita usam `ActiveRecord.after_all_transactions_commit` (padrão de `lead_state/completion_service.rb:74`).
- `AGENTS.md` "General Guidelines": falha alta em configuração impossível (arquivo versionado inválido levanta na carga; inbox mal configurado segue `QuoteInboxMisconfigured`); validação de parâmetro na borda (422 para `quote_email_validation_mode` não booleano); reuso do nativo (`ConversationReplyMailer`, `Attachment` nativo via `EmailThread.post!(attachments:)`, `Messages::MessageBuilder` com `private: true` como em `handoff_service.rb:75`, threading `Re: <mail_subject>` em `conversation_reply_mailer.rb:121-129`, nome do remetente pelo inbox em `conversation_reply_mailer.rb:92-102`); sem helpers de uso único; sem specs de helper customizado.
- `AGENTS.md` Enterprise: `docs/agents/architecture.md` declara `enterprise/` sem uso pelo ScanSolo; nenhum arquivo alterado tem par em `enterprise/` (T20 confere com `grep -rnE "enterprise/|Captain::"`).
- i18n (`AGENTS.md`): backend só em `config/locales/en.yml` (seção `scan_solo.quote.request_email.*`, textos em pt-BR como no resto do módulo); frontend só em `app/javascript/dashboard/i18n/locale/en/scansolo.json`. `scan_solo.quote.email.*` (instruções, bloco, `to_confirm`) não muda.
- Estilo (`docs/agents/coding_guidelines.md`): `class ScanSolo::…` compacta, 1 classe por arquivo, ≤ 150 colunas, header comment com RF/CT/RNF. Vue com `<script setup>`, Tailwind, sem strings soltas.
- RNF-07: specs com WebMock, ActionMailer `:test`, 0 LLM real, 0 segredo. Nenhuma task envia e-mail ou WhatsApp real.
- Specs existentes só mudam de expectativa por mudança prevista no SPEC, citando o requisito (ex.: a seção `.request` de `email_composer_spec.rb`, OC/RF-13 substituído por RF-02..RF-13). 0 `skip`/`pending`/`xit` novos.
- Validação (memória do projeto: o bundle do host está quebrado):
  - Specs Ruby: `docker exec scansolo-phase2-test sh -c 'cd /app && bundle exec rspec <paths>'`. Rubocop: `docker exec scansolo-phase2-test sh -c 'cd /app && bundle exec rubocop --force-exclusion <paths>'`.
  - Depois de T01: `docker exec scansolo-phase2-test sh -c 'cd /app && RAILS_ENV=test bundle exec rails db:migrate'` (se gerar duplicate-key de `installation_configs`, recriar o banco de teste antes da suíte).
  - Vitest: `pnpm test <paths>`. ESLint: `pnpm eslint <arquivos>` com os `.vue` explícitos (a varredura por diretório ignora `.vue`).
  - Gate de regressão: `./scripts/ralph-test.sh`.
- Commits: só locais, Conventional Commits (`feat(scansolo): …`, `test(scansolo): …`, `docs(agents): …`), sem referência ao Claude. Sem push, deploy ou merge.

### Componentes reaproveitados
- Chatwoot nativo: `Message` → `SendReplyJob` → `Email::SendOnEmailService` → `ConversationReplyMailer#email_reply` (anexos da mensagem, `Re: <mail_subject>`, From pelo `business_name` + `sender_name_type` do inbox); `Messages::StatusUpdateService` marca `failed` + `external_error` na exceção de envio; `Messages::MessageBuilder` para nota privada; ActiveStorage (`attachment.file.blob`, `byte_size`, `filename`).
- ScanSolo: `Quote::EmailThread.post!(attachments:, additional_attributes:)`, `Quote::EmailComposer` (`conversation_url`, `empty_block`, `instruction_lines`), `Quote::Mailbox`, `LeadState::Projection`, `Qualification::FieldResolver` (`CATALOG`, `contact_value`, `missing_labels`), `AiTurn::AttachmentReader` (`MAP_URL_PATTERN`, `location_link`, `urls`), `Messaging::DeliveryReconciler`, `AuditLogger`, `AiAgent::PublishService`, `AgentCenter.vue`/`agentCenterFields.js` (`FIELD_TYPES.CHECKBOX`).

## AS IS — Componentes impactados

```mermaid
flowchart LR
  CS["lead_state/completion_service.rb"] -->|"after commit"| QJ["jobs/scan_solo/quote_request_job.rb<br/>sem retry"]
  QJ --> RS["quote/request_service.rb"]
  RES["quote/resend_service.rb"] -->|"deliver!"| RS
  RS -->|"resolve!"| MB["quote/mailbox.rb"]
  MB -->|"lê"| CFG[("scan_solo_ai_agent_configs<br/>publicada")]
  RS -->|"compose"| EC["quote/email_composer.rb<br/>request: lista técnica"]
  EC -->|"lê"| PJ["lead_state/projection.rb"]
  PJ --> FR["qualification/field_resolver.rb"]
  RS -->|"post! sem anexos"| ET["quote/email_thread.rb"]
  ET --> MAIL["ConversationReplyMailer"]
  WR["lead_state/writer.rb"] -->|"grava campos"| LS[("scan_solo_lead_states")]
  LST["conversation_listener.rb"] -->|"reconcile_delivery"| DR["messaging/delivery_reconciler.rb"]
  LST -->|"incoming WhatsApp"| TURN["AiTurnJob"]
  TURN --> WR
  ACV["AgentCenter.vue"] --> ACC["ai_agent_configs_controller.rb"]
  ACC --> CFG
```

Hoje o `EmailComposer.request` lista identificação e todos os campos não faltantes, sem anexos, sem pendências e sem localização tratada; o job não tem retry e uma falha de envio só fica no `failed` da mensagem; nenhuma mudança depois do envio é comunicada ao comercial. A tela de configuração não tem o modo validação.

## TO BE — Componentes propostos

```mermaid
flowchart LR
  CS["lead_state/completion_service.rb"] -->|"after commit"| QJ["quote_request_job.rb (alterado)<br/>retry 1/5/15 min"]
  QJ --> RS["quote/request_service.rb (alterado)"]
  RES["quote/resend_service.rb (alterado)"] -->|"deliver!"| RS
  RS -->|"resolve!"| MB["quote/mailbox.rb"]
  RS -->|"snapshot"| SNAP["quote/request_email/snapshot.rb (novo)"]
  SNAP -->|"lê"| PJ["lead_state/projection.rb"]
  SNAP -->|"lê"| CFG[("ai_agent_configs publicada<br/>+ quote_email_validation_mode (alterado)")]
  RS -->|"render"| RE["quote/request_email.rb (novo)"]
  EC["quote/email_composer.rb (alterado)"] -->|"delega request"| RE
  RE --> CSN["request_email/company_short_name.rb (novo)"]
  RE --> SL["request_email/service_label.rb (novo)"]
  RE --> LL["request_email/location_links.rb (novo)"]
  RE --> PI["request_email/pending_items.rb (novo)"]
  SL -->|"lê"| YML[("config/scan_solo/quote_request_email.yml (novo)")]
  PI -->|"lê"| YML
  RS -->|"post! com anexos"| ET["quote/email_thread.rb"]
  ET --> MAIL["ConversationReplyMailer"]
  QJ -.->|"esgotou"| DFS["quote/delivery_failure_service.rb (novo)"]
  WR["lead_state/writer.rb (alterado)"] -->|"after commit"| SCH["quote/update_scheduler.rb (novo)"]
  LST["conversation_listener.rb (alterado)"] -->|"anexo ou mapa"| SCH
  SCH -->|"wait_until 10 min"| UJ["quote_request_update_job.rb (novo)"]
  UJ --> US["quote/update_service.rb (novo)"]
  US --> RE
  US -->|"post! Re: nativo"| ET
  US --> UPD[("scan_solo_quote_request_updates (novo)")]
  LST -->|"reconcile_delivery"| DR["messaging/delivery_reconciler.rb (alterado)"]
  DR -->|"failed"| DFS
  DFS -->|"nota privada"| WA["conversa WhatsApp da oportunidade"]
  ACV["AgentCenter.vue (alterado)"] --> ACC["ai_agent_configs_controller.rb (alterado)"]
  ACC --> CFG
```

T01/T02 criam as colunas, a tabela de atualizações e a flag em `FIELDS`; T03 cria o arquivo versionado e o loader; T05–T08 os colaboradores puros; T11 o `Snapshot`; T12 o `RequestEmail` e a delegação no `EmailComposer`; T13 altera `RequestService`/`ResendService`; T14 cria o `DeliveryFailureService` e o retry do `QuoteRequestJob`; T15 altera `DeliveryReconciler`/listener (falha assíncrona); T16 cria `UpdateService` + `QuoteRequestUpdateJob`; T17 cria o `UpdateScheduler` e os ganchos no `Writer` e no listener; T09/T10 alteram controller, jbuilder e `AgentCenter`.

## Tasks

### T01 — Migrações: flag de modo validação, snapshot renderizado, janela e tabela de atualizações
- **Files**: `db/migrate/20261010100001_add_quote_email_validation_mode_to_scan_solo_ai_agent_configs.rb`, `db/migrate/20261010100002_add_update_tracking_to_scan_solo_quote_requests.rb` (novos), `db/schema.rb`, `spec/db/scansolo_migrations_spec.rb`, `spec/db/scan_solo_quote_request_email_migrations_spec.rb` (novo)
- **Change**:
  - 100001: `add_column :scan_solo_ai_agent_configs, :quote_email_validation_mode, :boolean, default: true, null: false` (rascunho e publicadas existentes ficam `true`; nenhuma outra coluna tocada, OC/RNF-05).
  - 100002: em `scan_solo_quote_requests`: `rendered_snapshot` jsonb (nulo), `rendered_digest` string (nulo), `update_window_ends_at` datetime (nulo). `create_table :scan_solo_quote_request_updates` com `account_id` (bigint, not null, índice), `quote_request_id` (FK para `scan_solo_quote_requests`, not null), `version_digest` string not null, `message_id` bigint (nulo), `sent_at` datetime, timestamps; `add_index [:quote_request_id, :version_digest], unique: true` (RF-14 (c), RNF-05).
  - `spec/db/scansolo_migrations_spec.rb`: contagem 38 → 40, com comentário citando as 2 migrações.
- **Covers**: RF-14, RF-21, CT-05, RNF-05
- **Tests**: `scan_solo_quote_request_email_migrations_spec.rb`: depois de migrar, rascunho e publicada pré-existentes com `quote_email_validation_mode = true` e demais `FIELDS` iguais aos de antes; 2 linhas com o mesmo `(quote_request_id, version_digest)` → `ActiveRecord::RecordNotUnique`; `db:migrate` no container sem erro.
- **Risk**: Low — migrações só aditivas.
- **Dependencies**: none

### T02 — Modelos: `QuoteRequestUpdate`, associações e flag em `AiAgentConfig::FIELDS`
- **Files**: `app/models/scan_solo/quote_request_update.rb` (novo), `app/models/scan_solo/quote_request.rb`, `app/models/scan_solo/ai_agent_config.rb`, `spec/models/scan_solo/quote_request_update_spec.rb` (novo), `spec/models/scan_solo/quote_request_spec.rb`, `spec/services/scan_solo/ai_agent/publish_service_spec.rb`
- **Change**:
  - `ScanSolo::QuoteRequestUpdate` (`table_name` `scan_solo_quote_request_updates`): `belongs_to :quote_request`, `belongs_to :account`, `belongs_to :message, optional: true`; `validates :version_digest, presence: true, uniqueness: { scope: :quote_request_id }`.
  - `QuoteRequest`: `has_many :updates, class_name: 'ScanSolo::QuoteRequestUpdate', dependent: :destroy`. Annotate das colunas novas.
  - `AiAgentConfig::FIELDS` ganha `quote_email_validation_mode` (depois de `quote_recipient_email`), para o `PublishService` copiar a flag no snapshot (RF-21, verified at `publish_service.rb:34`).
- **Covers**: RF-12, RF-14, RF-21, CT-05
- **Tests**: `quote_request_update_spec.rb`: presença e unicidade de `version_digest` por solicitação. `publish_service_spec.rb`: rascunho com a flag `false` → publicar → publicada `false`; rascunho alterado sem publicar → publicada inalterada (RF-12 AC "mudança só no rascunho").
- **Risk**: Low.
- **Dependencies**: T01

### T03 — Arquivo versionado de rótulos de serviço e pendências por tipo (RF-04, RF-21, CT-05 (2), CT-07)
- **Files**: `config/scan_solo/quote_request_email.yml` (novo), `app/services/scan_solo/quote/request_email/settings.rb` (novo), `spec/services/scan_solo/quote/request_email/settings_spec.rb` (novo)
- **Change**:
  - YAML (não secreto, sem UI): `service_labels` — lista ordenada de `{ label, terms }`: `GeoRadar` ← `georadar`, `geo radar`, `gpr`; `Pipe Locator` ← `pipe locator`, `pipelocator`, `localizador de tubulação`; `combined_label: GeoRadar + Pipe Locator`. `pending_items_by_service` — `GeoRadar`, `Pipe Locator`, `GeoRadar + Pipe Locator` e `outro` → `[1, 2, 3, 4, 5, 6, 7, 8]` (índices do CT-07).
  - `ScanSolo::Quote::RequestEmail::Settings.load` lê o arquivo 1 vez (memoizado em constante/`class << self`) e levanta `ArgumentError` quando falta chave, existe chave de serviço fora das 4 permitidas ou índice fora de 1..8 / repetido (falha alta, `AGENTS.md`). Expõe `service_labels`, `combined_label` e `pending_indexes(service_key)`.
- **Covers**: RF-04, RF-08, RF-21, CT-05, CT-07
- **Tests**: `settings_spec.rb`: o arquivo real só tem as 4 chaves de serviço e índices 1..8 (AC do RF-21); um YAML de fixture com chave `Sondagem` ou índice 9 → `ArgumentError`. `grep -n "quote_email_validation_mode\|pending" app/views/api/v1/accounts/scan_solo/ai_agent_configs/_ai_agent_config.json.jbuilder` não mostra campo de tabela de pendências (só a flag, de T09).
- **Risk**: Low.
- **Dependencies**: none

### T04 — Textos fixos do i18n (`scan_solo.quote.request_email.*`) e varredura de conteúdo proibido (RF-16, RNF-06)
- **Files**: `config/locales/en.yml`, `spec/services/scan_solo/quote/request_email/texts_spec.rb` (novo)
- **Change**: sob `scan_solo.quote.request_email` (textos pt-BR literais do CT-01/CT-03/CT-07): `subject_prefix` (`Solicitação de orçamento`), `greeting` (`Olá, Luciano.`), `intro`, `validation_mode` (parágrafo literal do RF-12), `data_intro` (`No geral, seguem os dados coletados do lead:`), `sections.{client, location, service, objective, technical, other, documents, pending}`, `labels.{company, cnpj, contact, email, phone, unit, address, city_state, location, area, depth, deadline, safety}` (`Empresa`, `CNPJ`, `Contato`, `E-mail do solicitante`, `Telefone/WhatsApp do solicitante`, `Unidade / cliente final`, `Endereço informado`, `Cidade/UF`, `Localização informada pelo cliente (Google Maps)`, `Área/extensão`, `Profundidade de interesse`, `Prazo desejado`, `Integração de segurança`), `not_informed` (`não informado`), `service_not_informed` (`Serviço não informado`), `point` (`Ponto %{number}`), `no_documents`, `attachment_attached` (`- %{name} (%{type}) — anexado a este e-mail.`), `attachment_linked` (`- %{name} (%{type}) — disponível na conversa: %{link}`), `pending_items.{1..8}` (rótulos do CT-07), `closing_with_pending`, `closing_without_pending`, `conversation_link` (`Conversa no ScanSOLO`), `sign_off` (`Atenciosamente,`), `signature` (`Comercial ScanSolo`), `update.{header, change, new_attachment}` (`Atualização:`, `%{label}: %{previous} → %{current}`, `Novo anexo: %{name} (%{type})`), `failure_note` (motivo + link da conversa de e-mail, sem segredos). `scan_solo.quote.email.*` e `scan_solo.quote.block.*` intocados (RF-11).
- **Covers**: RF-02, RF-04, RF-09, RF-12, RF-16, RF-18, CT-01, CT-03, CT-07, RNF-06
- **Tests**: `texts_spec.rb` percorre todas as folhas de `I18n.t('scan_solo.quote.request_email')` e não acha `R$`, `IA` (palavra inteira), `inteligência artificial`, `sistema`, `token` nem `http`, exceto o `validation_mode` aprovado literalmente (RF-16 AC); `I18n.t` das chaves sem `translation missing`; `git diff <base> -- config/locales/en.yml` não altera linhas de `scan_solo.quote.email` nem `scan_solo.quote.block`.
- **Risk**: Low.
- **Dependencies**: none

### T05 — `CompanyShortName`: empresa curta por regra local (RF-03)
- **Files**: `app/services/scan_solo/quote/request_email/company_short_name.rb` (novo), `spec/services/scan_solo/quote/request_email/company_short_name_spec.rb` (novo)
- **Change**: `CompanyShortName.call(company:, contact_name:)`: sem `empresa` → `contact_name`. Senão remove repetidamente do fim, sem diferenciar maiúsculas e acentos (comparação por `I18n.transliterate(...).downcase`), os sufixos de uma constante `SUFFIXES` (no mínimo `Ltda.`, `Ltda`, `S.A.`, `S/A`, `SA`, `EIRELI`, `ME`, `EPP`, `MEI`, `Exportação e Importação`, `Importação e Exportação`, `Comércio`, `Indústria`; os mais longos primeiro), mais pontuação e espaços sobrando; resultado com menos de 2 caracteres → razão social inteira. Sem I/O.
- **Covers**: RF-03, RF-01
- **Tests**: `AMAGGI Exportação e Importação Ltda.` → `AMAGGI`; `ME Ltda.` → `ME Ltda.`; `Construtora Alfa S.A.` → `Construtora Alfa`; `construtora alfa sa` → `construtora alfa`; empresa vazia → nome do contato.
- **Risk**: Low.
- **Dependencies**: none

### T06 — `ServiceLabel`: rótulo do serviço pelo arquivo versionado (RF-04)
- **Files**: `app/services/scan_solo/quote/request_email/service_label.rb` (novo), `spec/services/scan_solo/quote/request_email/service_label_spec.rb` (novo)
- **Change**: `ServiceLabel.call(tipo_servico:, tecnologia:)` → `Result(label, service_key, informed)`. Normaliza o texto concatenado (sem maiúsculas e acentos) e procura os termos de `Settings.service_labels` (T03): termos dos 2 grupos → `combined_label`; 1 grupo → o rótulo dele; nenhum → o texto livre de `tipo_servico` (ou, sem ele, `tecnologia`) só com o tratamento do RF-02(b); os 2 vazios → `I18n.t('scan_solo.quote.request_email.service_not_informed')` com `informed: false`. `service_key` = o rótulo reconhecido ou `outro` (para o RF-08).
- **Covers**: RF-04, RF-21
- **Tests**: `tecnologia` = "GPR" → `GeoRadar`; `tipo_servico` = "Georadar e pipe locator" → `GeoRadar + Pipe Locator`; "Sondagem SPT" → `Sondagem SPT` e `service_key` `outro`; os 2 vazios → `Serviço não informado`, `informed` falso.
- **Risk**: Low.
- **Dependencies**: T03, T04

### T07 — `LocationLinks`: normalização e deduplicação de links de mapa (RF-10)
- **Files**: `app/services/scan_solo/quote/request_email/location_links.rb` (novo), `spec/services/scan_solo/quote/request_email/location_links_spec.rb` (novo)
- **Change**: `LocationLinks.call(sources:)` recebe a lista cronológica de URLs candidatas (montada pelo `Snapshot`, T11) e devolve a lista final de links. (a) Coordenadas extraídas de `q=`/`query=`/`ll=` ou `@lat,lng` → `https://www.google.com/maps?q={lat},{lng}`, preservando sinal, com 6 a 7 casas decimais (o valor original quando já tem 6–7; senão `format('%.7f')` sem zeros desnecessários abaixo de 6); (b) distância haversine < 50 m de um ponto já aceito → descartado (fica o primeiro); (c) o rótulo `Ponto N` é aplicado pelo renderizador (T12) quando há ≥ 2 itens; (d) `https` de host aceito por `ScanSolo::AiTurn::AttachmentReader::MAP_URL_PATTERN` sem coordenadas → entra como está, sem dedupe e sem HTTP; (e) não `https` ou host fora do padrão → descartado. Constante `DEDUP_METERS = 50`. Sem I/O.
- **Covers**: RF-10, RF-16, RF-01
- **Tests**: `-13.0053596,-55.9400673` + `-13.00536,-55.94007` → 1 link `https://www.google.com/maps?q=-13.0053596,-55.9400673`; 2 pontos a 2 km → 2 links na ordem; `https://maps.app.goo.gl/abc` → mantido; `http://evil.example/maps?q=1,1` e `https://evil.example/maps?q=1,1` → descartados; `@-13.1,-55.9,17z` reconhecido.
- **Risk**: Low.
- **Dependencies**: T04

### T08 — `PendingItems`: pendências por regra fixa (RF-08, CT-07)
- **Files**: `app/services/scan_solo/quote/request_email/pending_items.rb` (novo), `spec/services/scan_solo/quote/request_email/pending_items_spec.rb` (novo)
- **Change**: `PendingItems.call(missing_labels:, service:, values:, attachments:)`: grupo (1) = `missing_labels` (`FieldResolver#missing_labels`, ordem da config) + o rótulo do catálogo `Tipo de serviço` no fim quando `service.informed` é falso e ele ainda não está no grupo; grupo (2) = os índices de `Settings.pending_indexes(service.service_key)` (T03) cuja condição do CT-07 não é atendida — 1: `area` ou `metragem`; 2: `profundidade`; 3: `integracao_seguranca`; 4: `restricoes_acesso` ou `documentacoes_necessarias`; 5: `prazo_desejado` ou `data_desejada`; 6: ≥ 1 anexo `image`; 7: ≥ 1 anexo `.kmz`/`.kml`; 8: `condicoes_especiais` — com os rótulos de `scan_solo.quote.request_email.pending_items.N`. União sem repetição: grupo (2) na ordem do CT-07, depois grupo (1) na ordem da config (RF-08: "na ordem do CT-07 seguida da ordem da config"). Sem LLM.
- **Covers**: RF-08, RF-04, CT-07, RF-01
- **Tests**: exemplo do CT-01 (GeoRadar, sem área/profundidade/prazo/integração/fotos/KMZ/liberações/requisitos) → os 8 rótulos na ordem; tudo informado → lista vazia; só `documentacoes_necessarias` → item 4 ausente; `observacoes_tecnicas` sem `condicoes_especiais` → item 8 presente; serviço não informado → `Tipo de serviço` na lista; rótulo repetido entre grupos aparece 1 vez.
- **Risk**: Low.
- **Dependencies**: T03, T04

### T09 — API de configuração: `quote_email_validation_mode` com validação de borda (RF-21, CT-05 (1))
- **Files**: `app/controllers/api/v1/accounts/scan_solo/ai_agent_configs_controller.rb`, `app/views/api/v1/accounts/scan_solo/ai_agent_configs/_ai_agent_config.json.jbuilder`, `spec/requests/api/v1/accounts/scan_solo/ai_agent_configs_spec.rb`
- **Change**: `draft_params` permite `:quote_email_validation_mode`; `validate_commercial_params` acrescenta: se a chave vier e o valor não for `true`/`false` (JSON booleano) → `@draft.errors.add(:quote_email_validation_mode, 'must be a boolean')` → 422 pelo `RecordInvalid` existente (`request_exception_handler.rb:58`, padrão atual da tela). Sem coerção de `"true"`/`1` (`AGENTS.md`: aceitar só o tipo documentado). Jbuilder expõe `json.quote_email_validation_mode resource.quote_email_validation_mode` no rascunho e na publicada. Nenhum campo de tabela de pendências.
- **Covers**: RF-21, CT-05, UI-01
- **Tests**: PUT `draft` com `false` → 200 e rascunho `false`; com `"yes"` ou `1` → 422 com `attributes` contendo `quote_email_validation_mode`; publicar → GET mostra `published.quote_email_validation_mode = false`; GET sem mudança → `true` (padrão); agente não admin → 403 (política existente).
- **Risk**: Low.
- **Dependencies**: T02

### T10 — Tela de configuração: toggle "Modo validação do e-mail de solicitação" (UI-01)
- **Files**: `app/javascript/dashboard/routes/dashboard/scansolo/agent/agentCenterFields.js`, `app/javascript/dashboard/routes/dashboard/scansolo/agent/AgentCenter.vue`, `app/javascript/dashboard/i18n/locale/en/scansolo.json`, `app/javascript/dashboard/routes/dashboard/scansolo/agent/specs/AgentCenter.spec.js`
- **Change**: `AGENT_CENTER_FIELD_LABELS.quoteEmailValidationMode = 'SCANSOLO.AGENT_CENTER.FIELDS.QUOTE_EMAIL_VALIDATION_MODE'`; seção `commercial` ganha `{ name: 'quoteEmailValidationMode', type: FIELD_TYPES.CHECKBOX }` depois de `quoteRecipientEmail`; `AgentCenter.vue`: estado inicial `quoteEmailValidationMode: true`, carga a partir de `draft.quote_email_validation_mode` e `draftPayload` com `quote_email_validation_mode: form.quoteEmailValidationMode`; i18n `"QUOTE_EMAIL_VALIDATION_MODE": "Modo validação do e-mail de solicitação"`. Fluxo salvar/publicar existente; sem tela, rota ou menu novos; sem controle para pendências.
- **Covers**: UI-01, RF-21, RNF-06
- **Tests**: `AgentCenter.spec.js`: o checkbox aparece marcado com rascunho `true`; desmarcar e salvar → PUT com `quote_email_validation_mode: false`; publicar segue o fluxo atual. `pnpm eslint app/javascript/dashboard/routes/dashboard/scansolo/agent/AgentCenter.vue app/javascript/dashboard/routes/dashboard/scansolo/agent/agentCenterFields.js` sem erro (`vue/no-bare-strings-in-template`).
- **Risk**: Low.
- **Dependencies**: none (contrato do campo fixado em T09/`openapi.yaml`)

### T11 — `RequestEmail::Snapshot`: leitura determinística das fontes do CT-02
- **Files**: `app/services/scan_solo/quote/request_email/snapshot.rb` (novo), `spec/services/scan_solo/quote/request_email/snapshot_spec.rb` (novo)
- **Change**: `Snapshot.call(opportunity:, config:)` devolve um `Hash` canônico (chaves string, ordem fixa, só tipos JSON) — é a "versão da qualificação" do RF-14 e a entrada única do renderizador:
  - `fields`: para cada chave do CATALOG usada pelo CT-02 (`empresa`, `cnpj`, `nome`, `email`, `cliente_final`, `endereco_obra`, `bairro`, `cidade_uf`, `tipo_servico`, `tecnologia`, `interferencias_buscadas`, `tipo_intervencao`, `area`, `profundidade`, `prazo_desejado`, `integracao_seguranca` e as 16 de `outras_informacoes`), `{ value, inferred }` pela precedência do `FieldResolver` (lead state não `faltante` da `LeadState::Projection` → `FieldResolver.contact_value`), `value` com `strip`. `telefone` **não** é lido; `phone` = `contact.phone_number` (RF-07).
  - `contact_name`, `phone`, `missing_labels` (`FieldResolver.call(...).missing_labels`), `validation_mode` (`config.quote_email_validation_mode`), `conversation_url` (`EmailComposer.conversation_url` da conversa WhatsApp).
  - `location_sources`: em ordem cronológica de recebimento (`created_at`, `id`), o `link_local` do lead state, as `AttachmentReader.location_link` dos anexos `location` e as URLs `AttachmentReader.urls` das mensagens `incoming` da conversa WhatsApp da oportunidade que casam `MAP_URL_PATTERN` (o filtro https/host é do T07).
  - `attachments`: anexos `image`/`audio`/`video`/`file` das mensagens `incoming` dessa conversa, em ordem cronológica, `{ id, name, type, file_type, byte_size }`, com `type` = extensão em maiúsculas ou `file_type` sem extensão. Nenhum download.
  - Só leitura: 0 escritas, 0 HTTP, 0 LLM.
- **Covers**: RF-01, RF-05, RF-06, RF-07, RF-10, RF-13, RF-14, CT-02, RNF-01
- **Tests**: `snapshot_spec.rb`: precedência (lead state `confirmado` > `custom_attributes`; `faltante` cai no contato); `inferido` marcado; `telefone` do lead state ignorado e `phone` do contato; anexos e localizações só de mensagens `incoming` da conversa da oportunidade, em ordem; 2 chamadas com o mesmo estado → `==` e o mesmo `to_json`; `expect { ... }.not_to change(...)` em `Message`/`AuditEvent`/`LeadState`; WebMock sem requisições.
- **Risk**: Medium — define a base de comparação do RF-14; o formato é fixado aqui e reutilizado.
- **Dependencies**: T02

### T12 — `RequestEmail`: assunto e corpo do CT-01, atualização do CT-03 e delegação do `EmailComposer.request`
- **Files**: `app/services/scan_solo/quote/request_email.rb` (novo), `app/services/scan_solo/quote/email_composer.rb`, `spec/services/scan_solo/quote/request_email_spec.rb` (novo), `spec/services/scan_solo/quote/email_composer_spec.rb`
- **Change**:
  - `TEMPLATE_VERSION = 'quote_request_email.v2'`; `MAX_SUBJECT = 120`; `ATTACHMENT_LIMIT = 15 * 1024 * 1024`; `UF = %w[AC AL … TO]` (27 siglas).
  - `RequestEmail.render(snapshot:, attachment_ids: nil)` → `Result(email, attachment_ids)` (`email` = `EmailComposer::Email`):
    - Assunto (RF-02, RF-17): prefixo + `CompanyShortName` (T05) + `ServiceLabel` (T06) + ` | {cidade}/{uf}` só quando `cidade_uf` termina numa UF válida separada por `/`, `-`, `,` ou espaço; CR/LF/controles → espaço e `squish` em cada trecho; > 120 → trunca a empresa com `…` até 1 caractere + `…`, depois os trechos seguintes do fim para o começo; o rótulo do serviço fica inteiro sempre que couber.
    - Corpo na ordem do CT-01 (RF-05): linhas opcionais omitidas sem valor; obrigatórias (`Empresa`, `E-mail do solicitante`, `Endereço informado`, objetivo) com `não informado`; telefone com `não informado` (RF-07); `Unidade / cliente final` de `cliente_final`; `Endereço informado` com `bairro` acrescentado (`, `) quando não contido sem acento/caixa; `Cidade/UF:` logo abaixo, valor citado; localização pelo `LocationLinks` (T07), com `Ponto N` quando ≥ 2; SERVIÇO SOLICITADO começa com `Serviço não informado` quando aplicável, seguido das linhas `Rótulo do catálogo: valor` de `tipo_servico`, `tecnologia`, `interferencias_buscadas`; DETALHES TÉCNICOS só com ≥ 1 dos 4; OUTRAS INFORMAÇÕES (16 chaves, ordem do catálogo, rótulo do catálogo) antes de DOCUMENTAÇÃO RECEBIDA; documentação pelo RF-13 (acumula `byte_size` em ordem, anexa enquanto ≤ 15 MB; o 1º que passaria e todos os seguintes viram a linha "disponível na conversa"); pendências pelo `PendingItems` (T08), `* {item};`; exatamente 1 parágrafo final (RF-09); `Conversa no ScanSOLO:`; assinatura; e por fim `EmailComposer.instruction_lines` (instruções + bloco vazio, inalterados, RF-11). Parágrafo de modo validação logo após a abertura só com `validation_mode` (RF-12). Valores `inferido` com o sufixo `scan_solo.quote.email.to_confirm` (RF-06).
    - RF-11: toda linha de valor do lead que, normalizada como no parser, começa com um rótulo do OC/CT-04 + `:` ou é igual a um delimitador recebe um prefixo neutro (ver Open Questions Q1: o `- ` literal do SPEC é removido por `LEADING_MARKERS` do parser, `response_block_parser.rb:26,86`, e não neutraliza a linha). Texto do lead nunca reescrito (RF-06).
    - HTML: mesmo `build` atual (cada linha escapada, `<br>`), RF-17; os únicos `href` vêm dos links do RF-10 e do link da conversa.
    - `attachment_ids:` explícito (usado pela atualização) restringe a seleção do RF-13 aos anexos novos, com o limite de 15 MB só sobre eles (CT-03).
  - `RequestEmail.render_update(snapshot:, previous:)` → CT-03: `Atualização:`, 1 linha por item alterado (`{rótulo}: {anterior | não informado} → {novo}`; pendência, localização e anexo novo como `Novo anexo: {nome} ({tipo})`), linha em branco, o resumo do CT-01 de `DADOS DO CLIENTE` até a assinatura e o bloco do RF-11. Sem assunto (thread nativo `Re:`). `changed?(snapshot, previous)` compara a parte renderizada.
  - `EmailComposer`: `request(opportunity:, projection:)` dá lugar a `request(snapshot:)` que delega ao `RequestEmail.render(...).email`; `instruction_lines` passa a ser um método de classe público (usado por T12, sem mudar o texto). `correction`, `negotiation`, `approval_request`, `lead_proposal` intactos. Remover `identification_lines`/`collected_lines` e as chaves que ficarem sem uso só se nenhum outro chamador usar (`grep`).
- **Covers**: RF-01..RF-13, RF-16, RF-17, CT-01, CT-02, CT-03, CT-07, RNF-01, RNF-02, RNF-03
- **Tests**:
  - `request_email_spec.rb` (sem banco: `snapshot` como hash literal): exemplo AMAGGI → assunto exato `Solicitação de orçamento | AMAGGI | GeoRadar | Lucas do Rio Verde/MT`, `Telefone/WhatsApp do solicitante: não informado`, `Cidade/UF:` abaixo do endereço, 1 link, 1 linha "anexado a este e-mail", sem DETALHES TÉCNICOS, 8 pendências e parágrafo "com pendências"; sem `cidade_uf` → sem ` | ` final; `Zona rural` → assunto sem cidade e linha `Cidade/UF: Zona rural`; valores de 0, 1, 300 e 500 caracteres e `\r\n`/TAB → ≤ 120 caracteres, 0 controles, rótulo do serviço inteiro (RNF-02); serviço não informado (assunto, seção e pendência); lead sem `cnpj`/`cliente_final`/`nome`/detalhes → 0 linhas `CNPJ:`/`Unidade / cliente final:`/`Contato:`, 0 `DETALHES TÉCNICOS INFORMADOS`, nenhuma linha terminando em `:` fora do bloco; OUTRAS INFORMAÇÕES com `Metragem: 200 m` e `Condições especiais: NF até dia 20` nessa ordem antes de DOCUMENTAÇÃO e ausente sem chaves; `<b>antes</b>` citado no texto e escapado no HTML; `inferido` com `(a confirmar)`; 0 `(extraído da conversa)`; anexos 2 MB → anexado, 10 MB + 8 MB → 1º anexado e 2º com link, 16 MB → nunca anexado, total ≤ 15 MB (RNF-03); sem anexos → "Nenhum documento recebido até o momento."; modo validação ligado → 1 parágrafo, desligado → 0; com/sem pendências → exatamente 1 parágrafo final; `ResponseBlockParser.call(content: email.text)` → 0 valores preenchidos, inclusive com objetivo contendo a linha `Valor total: 10` (RF-11); texto termina com `EmailComposer.empty_block` byte a byte; HTML só com `href` permitidos (RF-16); `empresa` = `<script>x</script>\r\nBcc: a@b.c` → `&lt;script&gt;` e assunto sem CR/LF (RF-17); 2 renderizações → texto, HTML e assunto idênticos (RF-01). `render_update`: 1ª linha `Atualização:`, linha de Profundidade com `não informado → 3 m`, resumo completo e bloco ao fim.
  - `email_composer_spec.rb`: a seção `.request` muda de expectativa (OC/RF-13 substituído por RF-02..RF-13, citado no `describe`); as demais seções e `empty_block` passam sem mudança.
  - `spec/services/scan_solo/quote/response_block_parser_spec.rb` e `reply_processor_spec.rb` passam sem mudança (RF-11).
- **Risk**: Medium — maior peça de lógica; mitigada pelos casos-limite da lista do RNF-08 e pelo parser rodando sobre a saída.
- **Dependencies**: T04, T05, T06, T07, T08, T11

### T13 — `RequestService`/`ResendService`: modelo novo, anexos, snapshot e auditoria (RF-01, RF-13, RF-19, RF-20)
- **Files**: `app/services/scan_solo/quote/request_service.rb`, `app/services/scan_solo/quote/resend_service.rb`, `spec/services/scan_solo/quote/request_service_spec.rb`, `spec/services/scan_solo/quote/resend_service_spec.rb`
- **Change**:
  - `compose` passa a ser `render(opportunity)`: `snapshot = RequestEmail::Snapshot.call(opportunity:, config: AiAgentConfig.published_for(account))` e `RequestEmail.render(snapshot:)`. `create_request!` usa o assunto novo como `mail_subject` do thread (OC/CT-03 alterado).
  - `deliver!` (usado também pelo reenvio): `EmailThread.post!(…, attachments: Attachment.where(id: result.attachment_ids).order(:id).map { _1.file.blob }, additional_attributes: { 'scansolo_origin' => 'quote_request_email' })`; depois, `quote_request.update!(request_message_id:, sent_at:, rendered_snapshot: snapshot, rendered_digest: Digest::SHA256.hexdigest(snapshot.to_json), update_window_ends_at: nil)` — o reenvio passa a ser a base das próximas atualizações (RF-20). `request_message_id` segue o comportamento atual (gravado a cada envio, inclusive no reenvio).
  - Auditoria `quote_request.sent` (envio e reenvio): payload `{ quote_request_id, opportunity_id, template_version: RequestEmail::TEMPLATE_VERSION, recipient, message_id, result: 'sent' }` com o `correlation_id` da solicitação (RF-19, CT-06). Sem corpo nem dados pessoais além do destinatário.
  - Gatilho, `Mailbox`, unicidade, thread, aviso ao cliente (`post_customer_notice!`) e `record_misconfigured!` inalterados (RF-01, RF-20).
- **Covers**: RF-01, RF-13, RF-15, RF-19, RF-20, CT-01, CT-06, RNF-03, RNF-04
- **Tests**: `request_service_spec.rb` (ActionMailer `:test`, `perform_enqueued_jobs`): 1 mensagem com o assunto/corpo novos e 1 anexo de 2 MB (mesmo checksum do blob do lead); `rendered_digest` gravado; 1 `quote_request.sent` com os 5 campos do RF-19; WebMock sem requisições e um double de LLM que levanta se chamado → passa (RF-01); dentro de transação → `DeliveryInsideTransaction` (RNF-04). `resend_service_spec.rb`: 2 reenvios → 2 mensagens no mesmo thread com o formato novo, 1 solicitação, 0 avisos novos ao cliente, 0 `QuoteRequestUpdate`, `rendered_digest` do último envio (RF-20); expectativas antigas de corpo (OC/RF-13) substituídas citando RF-20.
- **Risk**: Medium — caminho central da solicitação; contrato de gatilho e unicidade preservado.
- **Dependencies**: T12

### T14 — `DeliveryFailureService` e retry 1/5/15 min do `QuoteRequestJob` (RF-18 caso A)
- **Files**: `app/services/scan_solo/quote/delivery_failure_service.rb` (novo), `app/jobs/scan_solo/quote_request_job.rb`, `spec/services/scan_solo/quote/delivery_failure_service_spec.rb` (novo), `spec/jobs/scan_solo/quote_request_job_spec.rb` (novo)
- **Change**:
  - `DeliveryFailureService.call(opportunity:, reason:, message: nil)` (fora de transação, RNF-04): idempotente por mensagem quando `message` existe (não repete se já há `quote_request.delivery_failed` com o mesmo `message_id` no payload); cria 1 nota privada na conversa WhatsApp da oportunidade com `Messages::MessageBuilder.new(nil, opportunity.conversation, { content: I18n.t('scan_solo.quote.request_email.failure_note', reason:, link:), private: true }).perform` (padrão de `handoff_service.rb:75`), com `link` = `EmailComposer.conversation_url` da conversa de e-mail da solicitação; grava 1 `AuditEvent` `quote_request.delivery_failed` com o `correlation_id` da solicitação e payload do CT-06 (`result` = motivo). `reason` = nome da classe da exceção (caso A) ou `external_error` truncado em 200 caracteres (caso B); nunca credenciais. Não muda etapa, status nem handoff.
  - `QuoteRequestJob`: `WAITS = [1.minute, 5.minutes, 15.minutes].freeze`; `retry_on StandardError, attempts: 4, wait: ->(executions) { WAITS.fetch(executions - 1) }` com bloco de esgotamento que chama `DeliveryFailureService` só se a solicitação continua sem `request_message_id` (falha antes de a mensagem existir). A reexecução reaproveita a solicitação sem `request_message_id` (comportamento atual, `request_service.rb:85-91`), então nunca cria 2ª solicitação nem thread.
- **Covers**: RF-18, RF-19, CT-06, RNF-04
- **Tests**: `quote_request_job_spec.rb` com `EmailThread.post!` levantando sempre e `perform_enqueued_jobs` + `travel`: exatamente 4 execuções, esperas de 1, 5 e 15 min (`have_been_enqueued.at`), depois 1 nota `private: true` na conversa WhatsApp, 1 `quote_request.delivery_failed`, 0 solicitações novas, 1 thread; exceção só na 1ª → 1 e-mail, 0 notas, 0 `delivery_failed`; durante a falha, `ScanSolo::Handoff::HandoffService.call` leva a conversa a `awaiting_human`. `delivery_failure_service_spec.rb`: 2 chamadas com a mesma mensagem → 1 nota e 1 auditoria; payload sem corpo do e-mail.
- **Risk**: Medium — `retry_on StandardError` amplo; limitado a 4 tentativas e à ausência de `request_message_id` para a nota.
- **Dependencies**: T04, T13

### T15 — Falha assíncrona da mensagem de e-mail: nota + auditoria na hora, sem retry (RF-18 caso B)
- **Files**: `app/services/scan_solo/messaging/delivery_reconciler.rb`, `app/services/scan_solo/conversation_listener.rb`, `spec/services/scan_solo/messaging/delivery_reconciler_spec.rb`, `spec/services/scan_solo/conversation_listener_spec.rb`
- **Change**: listener: `TEMPLATE_ORIGINS` ganha `quote_request_email` e `quote_request_update` (só classificação; o reconciliador já é chamado em `message_created`/`message_updated`). `DeliveryReconciler#call`: com `outcome == :failed` e origem de e-mail de solicitação/atualização, localiza a solicitação pela conversa de e-mail (`QuoteRequest.find_by(email_conversation_id: message.conversation_id)`) e chama `Quote::DeliveryFailureService.call(opportunity:, reason: external_error, message:)` (T14). Nenhuma nova mensagem no thread, nenhum retry (M-11). Os outros caminhos do reconciliador não mudam.
- **Covers**: RF-18, RNF-04
- **Tests**: `delivery_reconciler_spec.rb`: mensagem `quote_request_email` atualizada para `failed` com `external_error` → 0 mensagens novas no thread, 1 nota privada, 1 `delivery_failed`; 2º `message_updated` igual → continua 1; aceita (`source_id`) → nada. `conversation_listener_spec.rb`: `message_updated` de mensagem `quote_request_update` chama o reconciliador.
- **Risk**: Low.
- **Dependencies**: T14

### T16 — `UpdateService` + `QuoteRequestUpdateJob`: e-mail de atualização no mesmo thread (RF-14, CT-03)
- **Files**: `app/services/scan_solo/quote/update_service.rb` (novo), `app/jobs/scan_solo/quote_request_update_job.rb` (novo), `spec/services/scan_solo/quote/update_service_spec.rb` (novo), `spec/jobs/scan_solo/quote_request_update_job_spec.rb` (novo)
- **Change**:
  - `UpdateService.call(quote_request:)`:
    1. Sob `quote_request.with_lock`: `update_window_ends_at = nil` (fecha a janela; mudanças depois disso abrem outra); retorna se a solicitação não está `awaiting_reply`/`correction_requested` (RF-14 (a), checado no envio) ou não tem `request_message_id`/`rendered_snapshot`.
    2. `snapshot = Snapshot.call(...)`; `RequestEmail.changed?(snapshot, quote_request.rendered_snapshot)` falso → retorna (0 e-mails).
    3. Reivindica `QuoteRequestUpdate.create!(quote_request:, account:, version_digest: SHA256(snapshot.to_json))` numa transação; `RecordNotUnique` com mensagem já gravada → retorna; linha existente sem `message_id` (retry) → segue para o envio.
    4. Fora de transação: `settings = Mailbox.resolve!`; `EmailThread.post!(conversation: email_conversation, recipient: settings.recipient, email: RequestEmail.render_update(...).email, attachments: <blobs dos anexos novos até 15 MB>, additional_attributes: { 'scansolo_origin' => 'quote_request_update' })`; grava `message_id`/`sent_at` na linha e `rendered_snapshot`/`rendered_digest` na solicitação; 1 `AuditEvent` `quote_request.update_sent` (payload CT-06, `template_version`, `result: 'sent'`).
    - Não cria solicitação nem thread, não muda status, não posta aviso ao cliente (OC/RF-53).
  - `QuoteRequestUpdateJob` (`queue_as :medium`): `perform(quote_request_id)` chama o service; mesmo `retry_on` 1/5/15 min do T14 e, no esgotamento sem `message_id`, `DeliveryFailureService` (RF-18 vale para "solicitação ou atualização").
- **Covers**: RF-14, RF-18, RF-19, CT-03, CT-06, RNF-03, RNF-04, RNF-05
- **Tests**: `update_service_spec.rb` (ActionMailer `:test`): `profundidade` informada depois do envio → 1 mensagem no thread, assunto entregue `Re: <mail_subject>`, 1ª linha `Atualização:`, linha de Profundidade, resumo completo e bloco; reexecutar → continua 1; mudança que não altera nada renderizado → 0; status `replied` → 0; anexo novo de 2 MB → `Novo anexo:` e 1 anexo; 2 threads concorrentes → 1 e-mail (RNF-05); `quote_request.update_sent` com os 5 campos; 0 avisos ao cliente, status inalterado. `quote_request_update_job_spec.rb`: falha em todas → 4 tentativas e 1 nota no fim.
- **Risk**: Medium — e-mail extra ao comercial; limitado a 1 por versão (índice único) e por janela.
- **Dependencies**: T12, T13, T14

### T17 — `UpdateScheduler`: janela fixa de 10 min e ganchos de mudança (RF-14 (b))
- **Files**: `app/services/scan_solo/quote/update_scheduler.rb` (novo), `app/services/scan_solo/lead_state/writer.rb`, `app/services/scan_solo/conversation_listener.rb`, `spec/services/scan_solo/quote/update_scheduler_spec.rb` (novo), `spec/services/scan_solo/lead_state/writer_spec.rb`, `spec/services/scan_solo/conversation_listener_spec.rb`
- **Change**:
  - `UpdateScheduler.call(opportunity:)` (`WINDOW = 10.minutes`): retorna sem query extra se não há solicitação com `request_message_id` ou ela não está aberta; sob `quote_request.with_lock`, só quando `update_window_ends_at` é nulo grava `Time.current + WINDOW` e enfileira `QuoteRequestUpdateJob.set(wait_until:).perform_later(id)`. Janela aberta → nada (mudanças seguintes não reiniciam nem estendem).
  - `LeadState::Writer#write_field!`: `ActiveRecord.after_all_transactions_commit { ScanSolo::Quote::UpdateScheduler.call(opportunity: lead_state.opportunity) }` (só quando um campo muda de fato; transação revertida não agenda).
  - `ConversationListener#handle_incoming`: depois do fluxo atual, delega `UpdateScheduler.call(opportunity:)` só quando a mensagem tem anexo (`image`/`audio`/`video`/`file`/`location`) ou URL que casa `MAP_URL_PATTERN` (anexo e localização novos não passam pelo `Writer`). Sem outra lógica no listener.
- **Covers**: RF-14, RNF-04, RNF-05
- **Tests**: `update_scheduler_spec.rb` com `travel_to`: mudanças em t=0, t=2 e t=9 min → 1 job em t=10 min (janela não estendida); job executado em t=10 e mudança em t=11 → 2º job em t=21; solicitação `replied` ou sem `request_message_id` → 0 jobs; 2 chamadas concorrentes → 1 job. `writer_spec.rb`: `apply_field!` aplicado dentro de transação revertida → 0 jobs; aplicado e confirmado após o envio → 1 job; `:unchanged` → 0. `conversation_listener_spec.rb`: incoming com anexo `file` → agendador chamado; só texto sem mapa → não chamado. Fluxo AC do RF-14 (3 mudanças em 2 min → 1 e-mail com as 3) coberto em T18.
- **Risk**: Medium — gancho no `Writer` (único escritor do lead state) e no listener; ambos só agendam depois do commit e saem cedo sem solicitação enviada.
- **Dependencies**: T15, T16

### T18 — Provas ponta a ponta da feature (RNF-08)
- **Files**: `spec/services/scan_solo/quote/request_email_flow_spec.rb` (novo)
- **Change**: spec de integração (ActionMailer `:test`, WebMock, `perform_enqueued_jobs`, `travel_to`) cobrindo a lista do RNF-08 de ponta a ponta: conclusão → `QuoteRequestJob` → e-mail AMAGGI entregue com `From` = `Atendimento Comercial ScanSolo <atendimento.comercial@scansolo.com.br>` (inbox com `business_name` e `sender_name_type: professional`) e sem `Reply-To` diferente do nativo atual (RF-15); `empresa` maliciosa → e-mail entregue sem cabeçalho `Bcc` vindo do valor (RF-17); resposta do Luciano com bloco preenchido acima do e-mail novo citado → `ReplyProcessor` lê como hoje (RF-11); 3 mudanças em 2 min depois do envio → 1 atualização com as 3 ao fim da janela; `replied` no fim → 0; 1 envio + 1 atualização → busca por `correlation_id` devolve 1 `quote_request.sent` e 1 `quote_request.update_sent` com os 5 campos (RF-19); modo validação desligado e publicado → 0 parágrafos. Nenhum envio real.
- **Covers**: RF-11, RF-14, RF-15, RF-17, RF-19, RNF-07, RNF-08
- **Tests**: o próprio spec verde no container.
- **Risk**: Low.
- **Dependencies**: T09, T13, T14, T15, T16, T17

### T19 — Documentação de arquitetura e contratos
- **Files**: `docs/agents/domain_rules.md`, `docs/agents/architecture.md`, `docs/agents/data_model.md`, `docs/agents/api_contracts.md`
- **Change**: `domain_rules.md` "Quote request and reply" (modelo CT-01 determinístico, `template_version`, anexos ≤ 15 MB, atualização com janela fixa de 10 min só em `awaiting_reply`/`correction_requested`, retry 1/5/15 min e nota + `delivery_failed`, arquivo versionado `config/scan_solo/quote_request_email.yml`); `architecture.md` "Macro flow: quote to proposal" (Writer/listener → `UpdateScheduler` → `QuoteRequestUpdateJob` → `UpdateService`; reconciliador → `DeliveryFailureService`) e "Layer responsibilities" (origens novas no listener); `data_model.md` (colunas de `scan_solo_quote_requests`, tabela `scan_solo_quote_request_updates`, `quote_email_validation_mode`); `api_contracts.md` (campo novo do `ai_agent_config` e 422) com ponteiros para `.spec/features/scansolo-solicitacao-orcamento-email/openapi.yaml` e `asyncapi.yaml`. Editar só as seções citadas, preservando alterações locais existentes. Os docs operacionais citados no SPEC (`BACKLOG.md`, `DECISOES.md`, `STATUS_ATUAL.md`, `CHANGELOG.md`, `SYSTEM_MAP.md`, `claude/PLANO_AGENTE_E_PROPOSTAS.md`) não existem no repositório hoje: atualizar só os que existirem no momento da execução (`test -f`), sem criá-los.
- **Covers**: documentação de CT-01..CT-07
- **Tests**: `grep -n "quote_request.update_sent\|quote_request_email.v2\|quote_email_validation_mode" docs/agents/*.md` com ≥ 1 ocorrência em cada um dos 4 arquivos onde o tópico se aplica; `api_contracts.md` aponta os 2 contratos.
- **Risk**: Low.
- **Dependencies**: T09, T16, T17

### T20 — Gates de qualidade e regressão
- **Files**: nenhum arquivo novo; só corrige quebras residuais nos arquivos já alterados.
- **Change**: rodar e corrigir:
  - `bundle exec rubocop --force-exclusion` nos `.rb` alterados (container); `pnpm eslint` nos `.js/.vue` alterados (`.vue` explícitos); `pnpm test app/javascript/dashboard/routes/dashboard/scansolo/agent/specs`; `./scripts/ralph-test.sh`.
  - RF-11: `git diff <base> --stat -- app/services/scan_solo/quote/response_block_parser.rb app/services/scan_solo/quote/reply_processor.rb spec/services/scan_solo/quote/response_block_parser_spec.rb spec/services/scan_solo/quote/reply_processor_spec.rb` vazio; nenhuma linha de `scan_solo.quote.email`/`scan_solo.quote.block` alterada no `en.yml`.
  - RF-01/RNF-01: `grep -rnE "Net::HTTP|Faraday|HTTParty|SafeFetch|Llm|LLM|RubyLLM|OpenAI|\.save|\.update|\.create" app/services/scan_solo/quote/request_email.rb app/services/scan_solo/quote/request_email/` vazio.
  - RF-07: `git diff <base> -- app/services/scan_solo/ai_turn/ app/services/scan_solo/qualification/` vazio (prompt e lista de campos exigidos intactos).
  - OC/RF-53 / RF-14: `grep -n "post_customer_notice" app/services/scan_solo/quote/update_service.rb` vazio.
  - Sem `skip`/`pending`/`xit`: `git diff <base> -- spec app/javascript | grep -E '^\+\s*(skip|pending|xit|xdescribe|xcontext)\b|\b(it|describe|test)\.(skip|todo)\('` vazio.
  - Enterprise: `git diff <base> --name-only | xargs grep -lnE "enterprise/|Captain::"` vazio.
  - RNF-07: `grep -rnE "Bearer|api_access_token|password" config/scan_solo/quote_request_email.yml config/locales/en.yml | grep request_email` vazio.
- **Covers**: RF-01, RF-07, RF-11, RNF-01, RNF-06, RNF-07, RNF-08
- **Tests**: rubocop 0 offenses; eslint 0 erros; vitest verde; `./scripts/ralph-test.sh` exit 0.
- **Risk**: Low.
- **Dependencies**: T01..T19

### T21 — GATE HUMANO: nome de exibição do inbox de orçamento (RF-15)

> 2026-10-10: tarefa operacional movida do `PHASES.md` para `OPERADOR.md` (o ralph executa só as fases 1–10). PHASES.md tem 20 checkboxes para 21 tasks por isso. O envio de teste vai para o próprio e-mail do agente (ver `OPERADOR.md`).
- **Files**: `.spec/features/scansolo-operacao-centralizada/make/REGISTRO.md`
- **Change**: tarefa de operador, não executada pelo `ralph.sh` e sem nenhum envio de e-mail. Na instância de produção, no inbox publicado como `quote_inbox_id` (`atendimento.comercial@scansolo.com.br`), configurar `business_name` = `Atendimento Comercial ScanSolo` e `sender_name_type` = `professional` (Configurações do inbox → Nome do remetente). Conferir e registrar data, id do inbox e os 2 valores. Conferir também que a flag `quote_email_validation_mode` está publicada como `true` depois do deploy.
- **Covers**: RF-15, RF-21
- **Tests**: `GET /api/v1/accounts/<id>/inboxes/<quote_inbox_id>` → `business_name` e `sender_name_type` esperados; `GET .../scan_solo/ai_agent_config` → `published.quote_email_validation_mode = true`; linha datada no `REGISTRO.md`.
- **Risk**: Low.
- **Dependencies**: T20

## Execution Phases
| Phase | Tasks | Parallel-safe? |
|-------|-------|----------------|
| 1 — Fundação de dados: migrações | T01 | No (única; `db/schema.rb`) |
| 2 — Modelos, arquivo versionado e textos | T02, T03, T04 | Yes (modelos × YAML/loader × `en.yml`; arquivos disjuntos) |
| 3 — Colaboradores puros e configuração | T05, T06, T07, T08, T09, T10 | Yes (1 arquivo novo por colaborador; controller/jbuilder × frontend disjuntos) |
| 4 — Leitura das fontes (Snapshot) | T11 | No (única; fixa o formato usado por T12–T17) |
| 5 — Renderização CT-01/CT-03 | T12 | No (única; depende de T05–T08 e T11) |
| 6 — Envio: modelo novo e falha antes da mensagem | T13, T14 | No (T14 depende do `deliver!` de T13 e o job chama o service alterado) |
| 7 — Falha assíncrona e serviço de atualização | T15, T16 | Yes (reconciliador/listener × update service/job; arquivos disjuntos, ambos sobre T14) |
| 8 — Agendamento da janela de atualização | T17 | No (única; altera `conversation_listener.rb`, já tocado em T15) |
| 9 — Provas ponta a ponta e documentação | T18, T19 | Yes (spec × docs) |
| 10 — Gates de qualidade | T20 | No (depende de todo o código) |
| 11 — GATE HUMANO: nome de exibição do inbox — fora do `ralph.sh` | T21 | No (operacional) |

Deployabilidade:
- Phases 1–3 são aditivas: a flag nasce `true`, o toggle aparece e nada no envio muda ainda.
- Phases 4–8 devem ir juntas no mesmo deploy: a Phase 6 já envia o modelo novo e grava o snapshot que as Phases 7–8 usam como base; um deploy só até a Phase 6 é seguro (sem atualização, sem falha assíncrona tratada), mas não cumpre RF-14/RF-18 B.
- Phase 11 (operador) pode ser feita antes ou depois do deploy; sem ela o From sai com o nome padrão do inbox (não bloqueia o envio).

## Contracts emitted
| Artifact | Path | RFs covered | Compatibility |
|---|---|---|---|
| OpenAPI 3.1 (delta), v1.0.0 sobre OC v1.7.0 | `.spec/features/scansolo-solicitacao-orcamento-email/openapi.yaml` | CT-05 (1) → RF-21, UI-01 (`GET /ai_agent_config`, `PUT /ai_agent_config/draft`, `quote_email_validation_mode`); reenvio OC/CT-12 → RF-20 (sem mudança, referenciado) | Aditivo: campo booleano novo, padrão `true`, no rascunho e na publicada; valor não booleano → 422 com o corpo atual do `RecordInvalid` (`{ message, attributes }`). Nenhum campo existente muda nome, tipo ou sentido. O contrato do reenvio (OC/CT-12) é inalterado. |
| AsyncAPI 3.0 (delta), v1.0.0 sobre OC v1.5.0 | `.spec/features/scansolo-solicitacao-orcamento-email/asyncapi.yaml` | CT-01 → RF-01..RF-13, RF-15..RF-17, RF-20; CT-03 → RF-14; nota de falha → RF-18; CT-06 (auditoria) → RF-18, RF-19 | **Mudança intencional, sinalizada:** `QuoteRequestEmailPayload` do OC (CT-03) tinha `subject` com `pattern: '^Solicitação de orçamento #\d+ — .+$'` e corpo "identificação → todos os campos → bloco"; o SPEC (OC/RF-13 e OC/CT-03 alterados) troca o assunto para `Solicitação de orçamento | … | …` e o corpo para as seções do CT-01. O único consumidor é o comercial humano; o bloco OC/CT-04 e o `ResponseBlockParser` não mudam, então a leitura da resposta continua compatível. Canal novo de atualização (CT-03) no mesmo thread; `scansolo_origin` ganha `quote_request_email` e `quote_request_update` (aditivo); eventos de auditoria `quote_request.update_sent` e `quote_request.delivery_failed` novos e `quote_request.sent` com payload estendido (aditivo). |

Validação cruzada:
- Rastreabilidade: cada operação/canal cita RF/UI/CT na `description`. O arquivo versionado (CT-05 (2)) não é interface externa e não entra em contrato.
- Erros documentados: 422 de `quote_email_validation_mode` (CT-05); falhas de envio (RF-18 A/B) como nota + auditoria; 401/403/404 herdados do `BaseController`/Pundit.
- Nenhum campo sem RF: `quote_request_id` no payload de auditoria vem do CT-06.

## Risks
| Risk | Blast radius | Mitigation | Rollback |
|------|-------------|------------|----------|
| Assunto novo quebra filtros/regras de e-mail do comercial que procuravam `#<id>` | Caixa do Luciano | Assunto do CT-01 aprovado pelo desenvolvedor; avisar o comercial no deploy | Reverter T12/T13 (volta ao composer anterior) |
| Linha do lead neutralizada com `- ` continuaria lida pelo parser (Q1) | Leitura da resposta do comercial | Prefixo neutro que o parser não remove + spec do parser sobre a saída (T12) | Ajustar o prefixo; parser intocado |
| E-mails de atualização excessivos | Caixa do comercial | Só depois do envio, só em `awaiting_reply`/`correction_requested`, 1 por janela fixa de 10 min e por versão (índice único), 0 sem diferença renderizada | Remover os ganchos de T17 (o resto fica inerte) |
| Gancho no `Writer` (único escritor do lead state) | Todo turno do agente | Só `after_all_transactions_commit`, saída cedo sem solicitação enviada, spec de transação revertida | Reverter T17 |
| `retry_on StandardError` reexecuta um job que falhou depois de enviar | Solicitação | Reexecução reaproveita a solicitação; com `request_message_id` só retoma o aviso idempotente; nota só sem `request_message_id` | Reverter T14 |
| Anexos grandes atrasam o envio ou estouram o SMTP | Entrega do e-mail | Limite 15 MB por e-mail (RNF-03); o restante vai como link da conversa | Reduzir o limite (constante) |
| Solicitações enviadas antes do deploy não têm `rendered_snapshot` | Atualizações dessas solicitações | `UpdateService` não envia sem base (ver Assumptions); um reenvio manual grava a base | — |
| Nome de exibição não configurado no inbox | From do e-mail | T21 (operador), sem nome fixo no código | — |

Rollout:
1. Deploy das Phases 1–10 juntas (com `db:migrate`), conferindo no tracker e na auditoria o 1º `quote_request.sent` com `template_version = quote_request_email.v2`.
2. Phase 11 (operador): nome de exibição do inbox e flag publicada.
3. Avisar o comercial do assunto novo e do parágrafo de modo validação; desligar a flag pela tela quando o modelo estiver validado.

## Open Questions
- Q1 (SPEC × código, RF-11): o RF-11 manda prefixar com `- ` a linha de texto do lead que começa com um rótulo do OC/CT-04 + `:`, e o AC exige que o parser, rodando no e-mail sem resposta, devolva 0 valores. Mas o `ResponseBlockParser` remove marcadores iniciais `[\s*_\-•]+` antes de casar o rótulo (`LEADING_MARKERS`, verified at `app/services/scan_solo/quote/response_block_parser.rb:26,86,101`), então `- Valor total: 10` continua sendo lido como `total_value` — o prefixo literal não cumpre o AC, e o parser está fora do escopo. O plano segue o código e o AC: T12 usa um prefixo que o parser não remove nem trata como fronteira (default `» `, U+00BB), sem alterar o texto do lead. Confirmar o caractere (alternativas: `> `, que o parser trata como fronteira de citação; ou `(lead) `). Impacto: só linhas do lead que imitam o bloco.
- Q2 (nome da flag): o SPEC chama a flag de `modo_validacao` (RF-21, CT-05) e o FLEXIBLE sugere a coluna `quote_email_validation_mode`. O plano usa `quote_email_validation_mode` na coluna, no JSON da API e no `FIELDS` (padrão inglês das colunas `quote_*` da mesma config, `docs/agents/data_model.md`), tratando `modo_validacao` como o nome lógico do CT-02. Confirmar se o JSON da API deve expor literalmente `modo_validacao`.

## Assumptions
- O `ConversationReplyMailer` gera o From `"%{business_name} <%{from_email}>"` com `sender_name_type: professional` (verified at `app/mailers/conversation_reply_mailer.rb:92-102`) e não muda o Reply-To atual (`reply+<uuid>@<inbound_email_domain>` quando configurado, `conversation_reply_mailer.rb:136`); RF-15 é só configuração do inbox (T21) + spec (T18).
- O `deliver!` atual grava `request_message_id` com a mensagem de cada envio, inclusive no reenvio (verified at `app/services/scan_solo/quote/request_service.rb:47`); T13 mantém esse comportamento. O RF-14 só depende de o campo estar presente, e `rendered_snapshot`/`rendered_digest` passam a refletir o último e-mail enviado (RF-20).
- Solicitações enviadas antes do deploy (`rendered_snapshot` nulo) não recebem e-mail de atualização até um reenvio manual gravar a base; o SPEC trata a atualização como caso de borda mínimo.
- Mudanças só de coluna nativa do contato (nome, e-mail, telefone editados por um humano) não abrem janela de atualização: os gatilhos são o `Writer` (lead state) e mensagens `incoming` com anexo/localização/URL de mapa (T17). [UNVERIFIED se o SPEC espera esse caso; o RF-14 cita "campo do CT-02, pendência, localização ou anexo novo do lead".]
- A falha de reenvio manual síncrona (exceção no `ResendService`) continua devolvida ao administrador pela API, sem retry automático; o caso B (mensagem criada e depois `failed`) vale para envio, reenvio e atualização pelo reconciliador (T15).
- O motivo na nota privada é o nome da classe da exceção (caso A) ou o `external_error` nativo truncado (caso B); nenhum deles carrega credenciais do SMTP [UNVERIFIED para todos os provedores SMTP].
- `Messages::MessageBuilder` aceita `user = nil` para nota privada, como o `HandoffService` já usa com `actor` opcional (`handoff_service.rb:75`).
- Docs operacionais citados no SPEC não existem hoje (`test -f` falhou para os 6); T19 só os atualiza se existirem na execução.
- `db:migrate` no banco de teste pode gravar `installation_configs` e causar duplicate-key em specs (memória do projeto); se acontecer, recriar o banco de teste antes da suíte.
