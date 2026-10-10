# Phases: scansolo-solicitacao-orcamento-email

Gerado por /plan a partir de PLAN.md — view executável para `./ralph.sh .spec/features/scansolo-solicitacao-orcamento-email/PHASES.md`.

Regras transversais (de `AGENTS.md`/`CLAUDE.md`, `docs/agents/architecture.md`, `docs/agents/domain_rules.md`, `docs/agents/coding_guidelines.md`):
- Services: toda escrita e regra (`Quote::RequestService` único caminho da solicitação; `Quote::UpdateService` da atualização; `Quote::DeliveryFailureService` da nota + `quote_request.delivery_failed`). Jobs: retry e espera. Models: associações, validações e índices únicos. Listener: só classifica e delega.
- Montagem do e-mail (`ScanSolo::Quote::RequestEmail` e colaboradores): pura, 0 escritas, 0 HTTP, 0 LLM (RF-01, RNF-01). Leitura do banco só no `RequestEmail::Snapshot`.
- RNF-04: e-mail e nota privada só fora de transação (`EmailThread.post!` levanta `DeliveryInsideTransaction`); agendamentos a partir de escrita via `ActiveRecord.after_all_transactions_commit`.
- RF-11: `ResponseBlockParser`, `ReplyProcessor`, `scan_solo.quote.email.*` e `scan_solo.quote.block.*` intocados; o e-mail termina com `EmailComposer.instruction_lines` (instruções + bloco vazio) byte a byte iguais.
- i18n: backend só em `config/locales/en.yml` (`scan_solo.quote.request_email.*`, textos pt-BR); frontend só em `app/javascript/dashboard/i18n/locale/en/scansolo.json`. Sem strings soltas.
- Estilo: `class ScanSolo::…` compacta, 1 classe por arquivo, ≤150 colunas, header comment com RF/CT/RNF. Vue com `<script setup>` e Tailwind. Sem helpers de uso único.
- Specs Ruby e rubocop no container de teste: `docker exec scansolo-phase2-test sh -c 'cd /app && bundle exec rspec <paths>'` (rubocop: `bundle exec rubocop --force-exclusion <paths>`). Depois da Phase 1: `docker exec scansolo-phase2-test sh -c 'cd /app && RAILS_ENV=test bundle exec rails db:migrate'`. Vitest: `pnpm test <paths>`. ESLint com os `.vue` explícitos.
- RNF-07: WebMock, ActionMailer `:test`, 0 LLM real, 0 segredo. Nenhum envio real de e-mail ou WhatsApp.
- Specs existentes só mudam de expectativa por mudança prevista no SPEC, citando o requisito. Nunca `skip`/`pending`/`xit`.
- Commits só locais, Conventional Commits, sem referência ao Claude. Sem push, deploy ou merge.
- Base de comparação: o commit `docs(spec)` deste plano; até lá, `832721a15c`.
- A Phase 11 NÃO é executada pelo `ralph.sh`: é de operador (configuração do inbox na instância). O checkbox só é marcado `[x]` com a evidência descrita.

## Phase 1: Fundação de dados — migrações

Antes de implementar, leia:
1. `.spec/features/scansolo-solicitacao-orcamento-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-solicitacao-orcamento-email/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T01 — Migrações: flag de modo validação, snapshot renderizado, janela e tabela de atualizações
      Arquivos: `db/migrate/20261010100001_add_quote_email_validation_mode_to_scan_solo_ai_agent_configs.rb`, `db/migrate/20261010100002_add_update_tracking_to_scan_solo_quote_requests.rb` (novos), `db/schema.rb`, `spec/db/scansolo_migrations_spec.rb`, `spec/db/scan_solo_quote_request_email_migrations_spec.rb` (novo)
      Mudança: 100001 adiciona `quote_email_validation_mode` boolean `default: true, null: false` em `scan_solo_ai_agent_configs`; 100002 adiciona `rendered_snapshot` jsonb, `rendered_digest` string e `update_window_ends_at` datetime em `scan_solo_quote_requests` e cria `scan_solo_quote_request_updates` (`account_id`, `quote_request_id` FK, `version_digest` not null, `message_id`, `sent_at`, timestamps) com índice único `(quote_request_id, version_digest)`; contagem do `scansolo_migrations_spec` 38 → 40.
      Cobre: RF-14, RF-21, CT-05, RNF-05
      Acceptance criteria: configs pré-existentes (rascunho e publicada) ficam com `quote_email_validation_mode = true` e demais `FIELDS` iguais; inserir 2 `scan_solo_quote_request_updates` com o mesmo `(quote_request_id, version_digest)` levanta `ActiveRecord::RecordNotUnique`; `db:migrate` no container sem erro; `grep -nE "remove_column|rename_column|change_column|drop_table" db/migrate/20261010*` vazio.
      Testes: `spec/db/scan_solo_quote_request_email_migrations_spec.rb` — padrão true, valores preservados, unicidade; `spec/db/scansolo_migrations_spec.rb` — contagem 40.

## Phase 2: Modelos, arquivo versionado e textos

Antes de implementar, leia:
1. `.spec/features/scansolo-solicitacao-orcamento-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-solicitacao-orcamento-email/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T02 — Modelos: `QuoteRequestUpdate`, associações e flag em `AiAgentConfig::FIELDS`
      Arquivos: `app/models/scan_solo/quote_request_update.rb` (novo), `app/models/scan_solo/quote_request.rb`, `app/models/scan_solo/ai_agent_config.rb`, `spec/models/scan_solo/quote_request_update_spec.rb` (novo), `spec/models/scan_solo/quote_request_spec.rb`, `spec/services/scan_solo/ai_agent/publish_service_spec.rb`
      Mudança: `ScanSolo::QuoteRequestUpdate` (`belongs_to :quote_request`, `:account`, `:message` opcional; `version_digest` presente e único por solicitação); `QuoteRequest has_many :updates`; `AiAgentConfig::FIELDS` ganha `quote_email_validation_mode` para o `PublishService` copiar no snapshot.
      Cobre: RF-12, RF-14, RF-21, CT-05
      Acceptance criteria: `ScanSolo::AiAgentConfig::FIELDS.include?(:quote_email_validation_mode)`; rascunho `false` publicado → publicada `false`; rascunho alterado sem publicar → publicada inalterada; `QuoteRequestUpdate` sem `version_digest` inválido e duplicado por solicitação inválido.
      Testes: `quote_request_update_spec.rb` — validações; `publish_service_spec.rb` — cópia da flag e rascunho não publicado.
- [ ] T03 — Arquivo versionado de rótulos de serviço e pendências por tipo (RF-04, RF-21, CT-05 (2), CT-07)
      Arquivos: `config/scan_solo/quote_request_email.yml` (novo), `app/services/scan_solo/quote/request_email/settings.rb` (novo), `spec/services/scan_solo/quote/request_email/settings_spec.rb` (novo)
      Mudança: YAML com `service_labels` (GeoRadar ← `georadar`/`geo radar`/`gpr`; Pipe Locator ← `pipe locator`/`pipelocator`/`localizador de tubulação`), `combined_label` (`GeoRadar + Pipe Locator`) e `pending_items_by_service` (`GeoRadar`, `Pipe Locator`, `GeoRadar + Pipe Locator`, `outro` → `[1..8]`); `RequestEmail::Settings` carrega 1 vez e levanta `ArgumentError` para chave de serviço desconhecida, chave ausente ou índice fora de 1..8/repetido.
      Cobre: RF-04, RF-08, RF-21, CT-05, CT-07
      Acceptance criteria: o arquivo real tem exatamente as 4 chaves de serviço e só índices 1..8; fixture com chave extra ou índice 9 levanta `ArgumentError`; nenhum campo de pendências na config publicada nem no rascunho.
      Testes: `settings_spec.rb` — arquivo real válido, fixtures inválidas.
- [ ] T04 — Textos fixos do i18n (`scan_solo.quote.request_email.*`) e varredura de conteúdo proibido (RF-16, RNF-06)
      Arquivos: `config/locales/en.yml`, `spec/services/scan_solo/quote/request_email/texts_spec.rb` (novo)
      Mudança: chaves `scan_solo.quote.request_email.*` com os textos literais do CT-01/CT-03/CT-07 (prefixo do assunto, saudação, abertura, `validation_mode`, seções, rótulos, `não informado`, `Serviço não informado`, `Ponto %{number}`, linhas de anexo, 8 pendências, 2 parágrafos finais, link da conversa, assinatura, `Atualização:`, linha de mudança, `Novo anexo:`, `failure_note`); `scan_solo.quote.email.*` e `scan_solo.quote.block.*` intocados.
      Cobre: RF-02, RF-04, RF-09, RF-12, RF-16, RF-18, CT-01, CT-03, CT-07, RNF-06
      Acceptance criteria: nenhuma folha de `scan_solo.quote.request_email` contém `R$`, `IA` (palavra), `inteligência artificial`, `sistema`, `token` ou `http`, exceto o `validation_mode` aprovado literalmente; nenhuma chave nova retorna `translation missing`; `git diff <base> -- config/locales/en.yml` não altera linhas de `scan_solo.quote.email` nem `scan_solo.quote.block`.
      Testes: `texts_spec.rb` — varredura de conteúdo proibido e presença das chaves.

## Phase 3: Colaboradores puros e configuração

Antes de implementar, leia:
1. `.spec/features/scansolo-solicitacao-orcamento-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-solicitacao-orcamento-email/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-solicitacao-orcamento-email/openapi.yaml` — campo `quote_email_validation_mode` (T09, T10)

- [ ] T05 — `CompanyShortName`: empresa curta por regra local (RF-03)
      Arquivos: `app/services/scan_solo/quote/request_email/company_short_name.rb` (novo), `spec/services/scan_solo/quote/request_email/company_short_name_spec.rb` (novo)
      Mudança: remove repetidamente do fim (sem caixa e acento) os sufixos de `SUFFIXES` (Ltda., Ltda, S.A., S/A, SA, EIRELI, ME, EPP, MEI, Exportação e Importação, Importação e Exportação, Comércio, Indústria) e a pontuação/espaços que sobrarem; < 2 caracteres → razão social inteira; sem empresa → nome do contato. Sem I/O.
      Cobre: RF-03, RF-01
      Acceptance criteria: `AMAGGI Exportação e Importação Ltda.` → `AMAGGI`; `ME Ltda.` → `ME Ltda.`; `Construtora Alfa S.A.` → `Construtora Alfa`; empresa vazia → nome do contato.
      Testes: `company_short_name_spec.rb` — os 3 exemplos do AC, variação sem acento/caixa, empresa vazia.
- [ ] T06 — `ServiceLabel`: rótulo do serviço pelo arquivo versionado (RF-04)
      Arquivos: `app/services/scan_solo/quote/request_email/service_label.rb` (novo), `spec/services/scan_solo/quote/request_email/service_label_spec.rb` (novo)
      Mudança: `ServiceLabel.call(tipo_servico:, tecnologia:)` → `label`, `service_key` e `informed` pelos termos de `Settings` (T03); 2 grupos → rótulo combinado; nenhum termo → texto livre (`tipo_servico`, senão `tecnologia`) e `service_key` `outro`; os 2 vazios → `Serviço não informado` do i18n com `informed: false`.
      Cobre: RF-04, RF-21
      Acceptance criteria: "GPR" → `GeoRadar`; "Georadar e pipe locator" → `GeoRadar + Pipe Locator`; "Sondagem SPT" → `Sondagem SPT` com `service_key` `outro`; os 2 vazios → `Serviço não informado` e `informed` falso; o rótulo nunca é vazio.
      Testes: `service_label_spec.rb` — os 4 casos do AC.
- [ ] T07 — `LocationLinks`: normalização e deduplicação de links de mapa (RF-10)
      Arquivos: `app/services/scan_solo/quote/request_email/location_links.rb` (novo), `spec/services/scan_solo/quote/request_email/location_links_spec.rb` (novo)
      Mudança: a partir da lista cronológica de URLs, extrai coordenadas (`q=`/`query=`/`ll=`/`@lat,lng`) e normaliza para `https://www.google.com/maps?q={lat},{lng}` (6–7 casas, sinal preservado); descarta pontos a < 50 m (haversine) de um já aceito; mantém como está um `https` de host aceito por `AttachmentReader::MAP_URL_PATTERN` sem coordenadas; descarta não-`https` e hosts fora do padrão. Sem HTTP.
      Cobre: RF-10, RF-16, RF-01
      Acceptance criteria: `-13.0053596,-55.9400673` + `-13.00536,-55.94007` → 1 link `https://www.google.com/maps?q=-13.0053596,-55.9400673`; 2 pontos a 2 km → 2 links em ordem; `https://maps.app.goo.gl/abc` mantido; `http://evil.example/maps?q=1,1` ausente; WebMock sem requisições.
      Testes: `location_links_spec.rb` — dedupe, pontos distintos, link curto, URLs proibidas, formato `@lat,lng`.
- [ ] T08 — `PendingItems`: pendências por regra fixa (RF-08, CT-07)
      Arquivos: `app/services/scan_solo/quote/request_email/pending_items.rb` (novo), `spec/services/scan_solo/quote/request_email/pending_items_spec.rb` (novo)
      Mudança: itens do CT-07 de `Settings.pending_indexes(service_key)` cuja condição de "informado" falha (1 `area`/`metragem`; 2 `profundidade`; 3 `integracao_seguranca`; 4 `restricoes_acesso`/`documentacoes_necessarias`; 5 `prazo_desejado`/`data_desejada`; 6 anexo `image`; 7 anexo `.kmz`/`.kml`; 8 `condicoes_especiais`), na ordem do CT-07, seguidos dos `missing_labels` da config e de `Tipo de serviço` quando o serviço não foi informado; sem repetição; sem LLM.
      Cobre: RF-08, RF-04, CT-07, RF-01
      Acceptance criteria: exemplo do CT-01 → os 8 rótulos fixos na ordem; tudo informado → lista vazia; só `documentacoes_necessarias` → sem item 4; `observacoes_tecnicas` sem `condicoes_especiais` → item 8 presente; serviço não informado → `Tipo de serviço` presente; nenhum rótulo repetido.
      Testes: `pending_items_spec.rb` — os casos do AC.
- [ ] T09 — API de configuração: `quote_email_validation_mode` com validação de borda (RF-21, CT-05 (1))
      Arquivos: `app/controllers/api/v1/accounts/scan_solo/ai_agent_configs_controller.rb`, `app/views/api/v1/accounts/scan_solo/ai_agent_configs/_ai_agent_config.json.jbuilder`, `spec/requests/api/v1/accounts/scan_solo/ai_agent_configs_spec.rb`
      Mudança: permitir `:quote_email_validation_mode`; valor presente e não booleano → erro em `@draft.errors` → 422 pelo `RecordInvalid` atual; sem coerção; jbuilder expõe o campo no rascunho e na publicada.
      Cobre: RF-21, CT-05, UI-01
      Acceptance criteria: PUT `draft` com `false` → 200 e rascunho `false`; `"yes"` ou `1` → 422 com `attributes` contendo `quote_email_validation_mode`; publicar → `published.quote_email_validation_mode = false`; padrão `true` no GET; agente não admin → 403.
      Testes: `ai_agent_configs_spec.rb` — booleano aceito, não booleano 422, publicação, padrão.
- [ ] T10 — Tela de configuração: toggle "Modo validação do e-mail de solicitação" (UI-01)
      Arquivos: `app/javascript/dashboard/routes/dashboard/scansolo/agent/agentCenterFields.js`, `app/javascript/dashboard/routes/dashboard/scansolo/agent/AgentCenter.vue`, `app/javascript/dashboard/i18n/locale/en/scansolo.json`, `app/javascript/dashboard/routes/dashboard/scansolo/agent/specs/AgentCenter.spec.js`
      Mudança: rótulo `SCANSOLO.AGENT_CENTER.FIELDS.QUOTE_EMAIL_VALIDATION_MODE` ("Modo validação do e-mail de solicitação"); campo `quoteEmailValidationMode` `FIELD_TYPES.CHECKBOX` na seção `commercial`; estado inicial `true`, carga do rascunho e `draftPayload` com `quote_email_validation_mode`; fluxo salvar/publicar atual; sem tela, rota ou menu novos.
      Cobre: UI-01, RF-21, RNF-06
      Acceptance criteria: checkbox marcado com rascunho `true`; desmarcar e salvar → PUT com `quote_email_validation_mode: false`; `pnpm eslint` nos 2 arquivos (com o `.vue` explícito) sem erro; nenhuma string solta.
      Testes: `AgentCenter.spec.js` — renderização, toggle e payload.

## Phase 4: Leitura das fontes (Snapshot)

Antes de implementar, leia:
1. `.spec/features/scansolo-solicitacao-orcamento-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-solicitacao-orcamento-email/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T11 — `RequestEmail::Snapshot`: leitura determinística das fontes do CT-02
      Arquivos: `app/services/scan_solo/quote/request_email/snapshot.rb` (novo), `spec/services/scan_solo/quote/request_email/snapshot_spec.rb` (novo)
      Mudança: `Snapshot.call(opportunity:, config:)` → hash canônico com `fields` (chaves do CT-02 pela precedência do `FieldResolver`, `{ value, inferred }`), `contact_name`, `phone` só de `contact.phone_number`, `missing_labels`, `validation_mode`, `conversation_url`, `location_sources` (link_local + anexos `location` + URLs de mapa das mensagens `incoming` da conversa WhatsApp, em ordem cronológica) e `attachments` (`image`/`audio`/`video`/`file` `incoming`, `{ id, name, type, file_type, byte_size }`). Só leitura.
      Cobre: RF-01, RF-05, RF-06, RF-07, RF-10, RF-13, RF-14, CT-02, RNF-01
      Acceptance criteria: lead state não `faltante` prevalece sobre o contato; `telefone` do lead state ignorado; anexos e localizações só de mensagens `incoming` da conversa da oportunidade, em ordem; 2 chamadas com o mesmo estado → `to_json` idêntico; 0 escritas em `Message`/`AuditEvent`/`LeadState`; 0 requisições WebMock.
      Testes: `snapshot_spec.rb` — precedência, telefone, anexos, localização, determinismo, sem escrita.

## Phase 5: Renderização CT-01/CT-03

Antes de implementar, leia:
1. `.spec/features/scansolo-solicitacao-orcamento-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-solicitacao-orcamento-email/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-solicitacao-orcamento-email/asyncapi.yaml` — payloads CT-01 e CT-03

- [ ] T12 — `RequestEmail`: assunto e corpo do CT-01, atualização do CT-03 e delegação do `EmailComposer.request`
      Arquivos: `app/services/scan_solo/quote/request_email.rb` (novo), `app/services/scan_solo/quote/email_composer.rb`, `spec/services/scan_solo/quote/request_email_spec.rb` (novo), `spec/services/scan_solo/quote/email_composer_spec.rb`
      Mudança: `TEMPLATE_VERSION = 'quote_request_email.v2'`; `render(snapshot:, attachment_ids: nil)` → e-mail CT-01 (assunto RF-02 com UF das 27 siglas, sanitização e truncamento a 120; seções e omissões RF-05; telefone RF-07; localização T07 com `Ponto N`; pendências T08; parágrafo final RF-09; modo validação RF-12; anexos acumulados ≤ 15 MB RF-13; `(a confirmar)` RF-06; HTML escapado RF-17; prefixo neutro nas linhas do lead que imitam o bloco, RF-11/Q1 do PLAN; termina com `EmailComposer.instruction_lines`) + `attachment_ids`; `render_update(snapshot:, previous:)` → CT-03 (`Atualização:`, linhas de mudança, resumo, bloco); `changed?`. `EmailComposer.request(snapshot:)` delega; `instruction_lines` público; `correction`/`negotiation`/`approval_request`/`lead_proposal` intactos.
      Cobre: RF-01..RF-13, RF-16, RF-17, CT-01, CT-02, CT-03, CT-07, RNF-01, RNF-02, RNF-03
      Acceptance criteria: exemplo AMAGGI → assunto exatamente `Solicitação de orçamento | AMAGGI | GeoRadar | Lucas do Rio Verde/MT`, `Telefone/WhatsApp do solicitante: não informado`, `Cidade/UF:` abaixo do endereço, 1 link, 1 "anexado a este e-mail", sem DETALHES TÉCNICOS, 8 pendências e o parágrafo "com pendências"; sem `cidade_uf` → `Solicitação de orçamento | AMAGGI | GeoRadar`; valores de 300/500 caracteres e `\r\n` → assunto ≤ 120 e 0 controles, rótulo do serviço inteiro; OUTRAS INFORMAÇÕES só com chaves preenchidas e antes de DOCUMENTAÇÃO; 10 MB + 8 MB → 1 anexado e 1 com link; 16 MB nunca anexado; modo validação ligado → 1 parágrafo, desligado → 0; `ResponseBlockParser.call(content: email.text)` → 0 valores, inclusive com objetivo contendo `Valor total: 10`; texto termina com `EmailComposer.empty_block`; HTML com `&lt;script&gt;` e só `href` permitidos; 2 renderizações idênticas byte a byte; `response_block_parser_spec.rb` e `reply_processor_spec.rb` passam sem mudança.
      Testes: `request_email_spec.rb` — todos os casos do RNF-08 de montagem e `render_update`; `email_composer_spec.rb` — seção `.request` com expectativas de OC/RF-13 substituídas por RF-02..RF-13, demais seções inalteradas.

## Phase 6: Envio — modelo novo e falha antes da mensagem

Antes de implementar, leia:
1. `.spec/features/scansolo-solicitacao-orcamento-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-solicitacao-orcamento-email/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-solicitacao-orcamento-email/asyncapi.yaml` — e-mail CT-01, nota de falha e auditoria CT-06

- [ ] T13 — `RequestService`/`ResendService`: modelo novo, anexos, snapshot e auditoria (RF-01, RF-13, RF-19, RF-20)
      Arquivos: `app/services/scan_solo/quote/request_service.rb`, `app/services/scan_solo/quote/resend_service.rb`, `spec/services/scan_solo/quote/request_service_spec.rb`, `spec/services/scan_solo/quote/resend_service_spec.rb`
      Mudança: montar via `RequestEmail::Snapshot` + `RequestEmail.render`; `mail_subject` do thread com o assunto novo; `deliver!` posta com os blobs dos `attachment_ids` e `scansolo_origin: 'quote_request_email'`, grava `rendered_snapshot`, `rendered_digest` (SHA-256 do JSON) e zera `update_window_ends_at`; `quote_request.sent` com `{ quote_request_id, opportunity_id, template_version, recipient, message_id, result: 'sent' }`. Gatilho, mailbox, unicidade, thread e aviso ao cliente inalterados.
      Cobre: RF-01, RF-13, RF-15, RF-19, RF-20, CT-01, CT-06, RNF-03, RNF-04
      Acceptance criteria: 1 mensagem com o assunto/corpo novos e 1 anexo com o checksum do blob do lead; `rendered_digest` gravado; 1 `quote_request.sent` com os 5 campos do RF-19 e sem corpo; WebMock sem requisições e double de LLM nunca chamado; dentro de transação → `DeliveryInsideTransaction`; 2 reenvios → 2 mensagens no mesmo thread, 1 solicitação, 0 avisos novos, 0 `QuoteRequestUpdate`.
      Testes: `request_service_spec.rb` — envio, anexo, auditoria, RF-01, RNF-04; `resend_service_spec.rb` — reenvio no formato novo, expectativas de OC/RF-13 substituídas citando RF-20.
- [ ] T14 — `DeliveryFailureService` e retry 1/5/15 min do `QuoteRequestJob` (RF-18 caso A)
      Arquivos: `app/services/scan_solo/quote/delivery_failure_service.rb` (novo), `app/jobs/scan_solo/quote_request_job.rb`, `spec/services/scan_solo/quote/delivery_failure_service_spec.rb` (novo), `spec/jobs/scan_solo/quote_request_job_spec.rb` (novo)
      Mudança: `DeliveryFailureService.call(opportunity:, reason:, message: nil)` cria 1 nota privada (`Messages::MessageBuilder`, `private: true`) na conversa WhatsApp com motivo e link da conversa de e-mail e 1 `quote_request.delivery_failed` (payload CT-06, `correlation_id` da solicitação), idempotente por mensagem, fora de transação, sem mudar etapa/status/handoff; `QuoteRequestJob` com `retry_on StandardError, attempts: 4` e esperas 1/5/15 min; no esgotamento, só sem `request_message_id`, chama o service.
      Cobre: RF-18, RF-19, CT-06, RNF-04
      Acceptance criteria: exceção em todas as tentativas → exatamente 4 execuções (esperas de 1, 5 e 15 min), 1 nota `private: true` na conversa WhatsApp, 1 `quote_request.delivery_failed`, 0 solicitações novas e 1 thread; exceção só na 1ª → 1 e-mail, 0 notas, 0 `delivery_failed`; handoff durante a falha leva a `awaiting_human`; 2 chamadas do service com a mesma mensagem → 1 nota.
      Testes: `quote_request_job_spec.rb` — retry, esgotamento, sucesso na 2ª, handoff; `delivery_failure_service_spec.rb` — nota, auditoria, idempotência.

## Phase 7: Falha assíncrona e serviço de atualização

Antes de implementar, leia:
1. `.spec/features/scansolo-solicitacao-orcamento-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-solicitacao-orcamento-email/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-solicitacao-orcamento-email/asyncapi.yaml` — e-mail de atualização CT-03, eventos nativos e auditoria

- [ ] T15 — Falha assíncrona da mensagem de e-mail: nota + auditoria na hora, sem retry (RF-18 caso B)
      Arquivos: `app/services/scan_solo/messaging/delivery_reconciler.rb`, `app/services/scan_solo/conversation_listener.rb`, `spec/services/scan_solo/messaging/delivery_reconciler_spec.rb`, `spec/services/scan_solo/conversation_listener_spec.rb`
      Mudança: `TEMPLATE_ORIGINS` ganha `quote_request_email` e `quote_request_update`; o reconciliador, com `outcome == :failed` nessas origens, acha a solicitação pela conversa de e-mail e chama `Quote::DeliveryFailureService` com o `external_error`; nenhum retry nem mensagem nova.
      Cobre: RF-18, RNF-04
      Acceptance criteria: mensagem `quote_request_email` marcada `failed` com `external_error` → 0 mensagens novas no thread, 1 nota privada e 1 `delivery_failed` na hora; 2º update igual → continua 1; mensagem aceita (`source_id`) → nada; os specs atuais do reconciliador seguem verdes.
      Testes: `delivery_reconciler_spec.rb` — falha, idempotência, aceite; `conversation_listener_spec.rb` — origem nova reconciliada.
- [ ] T16 — `UpdateService` + `QuoteRequestUpdateJob`: e-mail de atualização no mesmo thread (RF-14, CT-03)
      Arquivos: `app/services/scan_solo/quote/update_service.rb` (novo), `app/jobs/scan_solo/quote_request_update_job.rb` (novo), `spec/services/scan_solo/quote/update_service_spec.rb` (novo), `spec/jobs/scan_solo/quote_request_update_job_spec.rb` (novo)
      Mudança: sob lock fecha a janela (`update_window_ends_at = nil`) e sai se não está `awaiting_reply`/`correction_requested` ou sem base; sem diferença renderizada → sai; reivindica `QuoteRequestUpdate` por `(quote_request_id, version_digest)`; fora de transação posta `render_update` no thread com os anexos novos até 15 MB e `scansolo_origin: 'quote_request_update'`; grava mensagem, snapshot/digest e `quote_request.update_sent`. Não cria solicitação/thread, não muda status, não avisa o cliente. Job com o mesmo retry 1/5/15 min e nota no esgotamento.
      Cobre: RF-14, RF-18, RF-19, CT-03, CT-06, RNF-03, RNF-04, RNF-05
      Acceptance criteria: `profundidade` informada depois do envio → 1 mensagem no thread com assunto entregue `Re: <mail_subject>`, 1ª linha `Atualização:`, a mudança de Profundidade e o resumo completo; reexecutar → continua 1; sem diferença renderizada → 0; status `replied` → 0; 2 threads concorrentes → 1 e-mail; `quote_request.update_sent` com os 5 campos; 0 avisos ao cliente e status inalterado; falha em todas as tentativas → 4 execuções e 1 nota.
      Testes: `update_service_spec.rb` — envio, idempotência, sem diferença, `replied`, anexo novo, concorrência; `quote_request_update_job_spec.rb` — retry e esgotamento.

## Phase 8: Agendamento da janela de atualização

Antes de implementar, leia:
1. `.spec/features/scansolo-solicitacao-orcamento-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-solicitacao-orcamento-email/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T17 — `UpdateScheduler`: janela fixa de 10 min e ganchos de mudança (RF-14 (b))
      Arquivos: `app/services/scan_solo/quote/update_scheduler.rb` (novo), `app/services/scan_solo/lead_state/writer.rb`, `app/services/scan_solo/conversation_listener.rb`, `spec/services/scan_solo/quote/update_scheduler_spec.rb` (novo), `spec/services/scan_solo/lead_state/writer_spec.rb`, `spec/services/scan_solo/conversation_listener_spec.rb`
      Mudança: `UpdateScheduler.call(opportunity:)` sai cedo sem solicitação enviada e aberta; sob lock, só com `update_window_ends_at` nulo grava `agora + 10 min` e enfileira `QuoteRequestUpdateJob.set(wait_until:)`; `Writer#write_field!` agenda via `after_all_transactions_commit`; `ConversationListener#handle_incoming` delega ao agendador só para mensagens com anexo ou URL de mapa.
      Cobre: RF-14, RNF-04, RNF-05
      Acceptance criteria: mudanças em t=0, 2 e 9 min → 1 job para t=10 min; mudança em t=11 após o job → 2º job para t=21; `replied` ou sem `request_message_id` → 0 jobs; 2 chamadas concorrentes → 1 job; transação revertida no `Writer` → 0 jobs; `apply_field!` `:unchanged` → 0 jobs; incoming só texto sem mapa → agendador não chamado.
      Testes: `update_scheduler_spec.rb` — janela fixa e concorrência; `writer_spec.rb` — commit × rollback; `conversation_listener_spec.rb` — anexo × texto.

## Phase 9: Provas ponta a ponta e documentação

Antes de implementar, leia:
1. `.spec/features/scansolo-solicitacao-orcamento-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-solicitacao-orcamento-email/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-solicitacao-orcamento-email/openapi.yaml` e `.spec/features/scansolo-solicitacao-orcamento-email/asyncapi.yaml` — contratos a referenciar nos docs

- [ ] T18 — Provas ponta a ponta da feature (RNF-08)
      Arquivos: `spec/services/scan_solo/quote/request_email_flow_spec.rb` (novo)
      Mudança: spec de integração (ActionMailer `:test`, WebMock, `perform_enqueued_jobs`, `travel_to`): conclusão → e-mail AMAGGI entregue com From do inbox; `empresa` maliciosa sem `Bcc`; resposta do Luciano lida como hoje; 3 mudanças em 2 min → 1 atualização; `replied` → 0; auditorias por `correlation_id`; modo validação desligado e publicado → 0 parágrafos. Nenhum envio real.
      Cobre: RF-11, RF-14, RF-15, RF-17, RF-19, RNF-07, RNF-08
      Acceptance criteria: `From` = `Atendimento Comercial ScanSolo <atendimento.comercial@scansolo.com.br>` com o inbox `business_name`/`professional` e sem Reply-To diferente do nativo; e-mail entregue sem cabeçalho `Bcc` vindo do valor; `ReplyProcessor` grava o bloco preenchido da resposta; 1 atualização com as 3 mudanças; 0 em `replied`; 1 `quote_request.sent` + 1 `quote_request.update_sent` com os 5 campos; spec verde no container.
      Testes: o próprio spec.
- [ ] T19 — Documentação de arquitetura e contratos
      Arquivos: `docs/agents/domain_rules.md`, `docs/agents/architecture.md`, `docs/agents/data_model.md`, `docs/agents/api_contracts.md`
      Mudança: "Quote request and reply" (modelo CT-01, `template_version`, anexos, atualização com janela fixa, retry e nota de falha, arquivo versionado); "Macro flow: quote to proposal" e "Layer responsibilities"; colunas e tabela novas; campo `quote_email_validation_mode` e 422 com ponteiros para os 2 contratos. Só as seções citadas, preservando alterações locais. Docs operacionais do SPEC só se existirem (`test -f`), sem criá-los.
      Cobre: documentação de CT-01..CT-07
      Acceptance criteria: `grep -n "quote_request.update_sent\|quote_request_email.v2\|quote_email_validation_mode" docs/agents/*.md` com ocorrência nos arquivos onde o tópico se aplica; `api_contracts.md` aponta `openapi.yaml` e `asyncapi.yaml` desta feature; nenhum doc operacional criado do zero.
      Testes: os greps do critério.

## Phase 10: Gates de qualidade

Antes de implementar, leia:
1. `.spec/features/scansolo-solicitacao-orcamento-email/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-solicitacao-orcamento-email/PLAN.md` — decomposição completa, dependências e riscos

- [ ] T20 — Gates de qualidade e regressão
      Arquivos: nenhum arquivo novo; só correções residuais nos arquivos já alterados.
      Mudança: rubocop nos `.rb` alterados (container), eslint nos `.js/.vue` alterados, vitest dos specs do AgentCenter, `./scripts/ralph-test.sh`, e os greps de RF-11 (parser/ReplyProcessor/chaves `quote.email`/`quote.block` sem diff), RF-01 (sem HTTP/LLM/escrita em `request_email*`), RF-07 (sem diff em `ai_turn/` e `qualification/`), OC/RF-53 (sem aviso no `update_service.rb`), sem `skip`/`pending`/`xit`, sem `enterprise/`/`Captain::`, sem segredos no YAML/i18n novos.
      Cobre: RF-01, RF-07, RF-11, RNF-01, RNF-06, RNF-07, RNF-08
      Acceptance criteria: rubocop 0 offenses; eslint 0 erros; vitest verde; `./scripts/ralph-test.sh` exit 0; todos os greps listados no PLAN (T20) vazios.
      Testes: os comandos acima.

