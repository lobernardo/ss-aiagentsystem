# ScanSolo Production Complete — Decisões Necessárias

Gerado em 2026-09-23 a partir do commit 4af19b0bb (branch feat/scansolo-production-complete). Documento factual — não implementa nada.

Documentos relacionados: [CURRENT_STATE](CURRENT_STATE.md) · [ARCHITECTURE_MAP](ARCHITECTURE_MAP.md) · [GAP_ANALYSIS](GAP_ANALYSIS.md) · [RISK_REGISTER](RISK_REGISTER.md)

Este documento lista só o que depende de uma pessoa: dados, credenciais ou política que não podem ser deduzidos do repositório.

**Regra para credenciais:** nenhum valor de segredo entra no Git, em issue ou neste documento. Registre apenas *onde* o segredo fica armazenado.

**Quem responde (papéis prováveis):**
- **Dono do produto:** ScanSolo / comercial.
- **Ops:** quem administra a VPS.
- **Admin Meta:** Business Manager / WABA.
- **Dono do Make.**
- **Dev.**

---

## Resumo

| ID | Tema | Bloqueia | Quem |
|---|---|---|---|
| D-01 | Credenciais Meta (WABA ID, Phone Number ID, token de System User) | WhatsApp em produção, sync de templates | Admin Meta |
| D-02 | App Secret da Meta para validar assinatura | Segurança do webhook (RR-S1) | Admin Meta + Ops |
| D-03 | Templates definitivos por passo de cadência e para envio de proposta | Cadências, envio de proposta | Produto + Admin Meta |
| D-04 | Endpoint e contrato Make reais; variáveis de preço | Propostas reais (P0-3) | Dono do Make + Produto |
| D-05 | Política de aprovação de proposta | Fluxo de proposta | Produto |
| D-06 | Abordagem inicial de Novo Lead | Cadência Novo Lead | Produto |
| D-07 | O que cria uma `PipelineOpportunity` e quando inscrever em cadência | Pipeline, cadências (P0-2, P0-13) | Produto |
| D-08 | Política de transições do pipeline | Matriz de transições | Produto/Comercial |
| D-09 | Resposta humana, rajadas e opt-out | Anti dupla resposta (P0-6) | Produto |
| D-10 | Canais e inboxes atendidos pela IA; URL/origem do site para o widget | Widget, restrição por inbox | Produto + Ops |
| D-11 | Escopo de crawl do site | Fonte URL/site | Produto |
| D-12 | Tecnologia do crawler | Fonte URL/site | Dev + Produto |
| D-13 | Suporte a PDF | Fonte PDF | Produto + Dev |
| D-14 | Fonte LEXUS e mapeamento de campos | Import LEXUS | Dono do LEXUS + Dev |
| D-15 | Usuários Comercial, papéis e quem publica config/knowledge | Área 17, policies | Produto/Gestão |
| D-16 | Dados SMTP | Convite de usuários, recuperação de senha | Ops |
| D-17 | Precedência Captain × ScanSolo | Dupla resposta (P0-7) | Produto + Dev |
| D-18 | Campos técnicos visíveis aos operadores | UX dos módulos | Produto |
| D-19 | Estratégia de locale en × pt_BR | i18n | Produto + Dev |
| D-20 | Comando de compose de produção, origem de `POSTGRES_PASSWORD`, ambiente de build | Deploy (P0-8, P0-9) | Ops |
| D-21 | Mecanismo de kill switch e dono único | Cutover (P0-14) | Produto + Ops |
| D-22 | Comportamento fora do horário e formato de limites de resposta | Uso de `service_hours`/`response_limits` | Produto |
| D-23 | Orçamento e limites de custo LLM/embeddings | Rate limits, alertas | Produto/Financeiro |

---

## Detalhe

### D-01 — Credenciais Meta
- **Pergunta.** Quais são o WABA ID, o Phone Number ID e o token permanente de System User do número de produção? Em qual inbox Chatwoot eles serão cadastrados?
- **Por que importa.**
  - O canal nativo guarda esses dados em `channel_whatsapp.provider_config` (`app/models/channel/whatsapp.rb`).
  - O sync de templates (`whatsapp_cloud_service.rb:35-45`) e o envio dependem deles.
- **O que bloqueia.** Qualquer tráfego WhatsApp real, o sync de templates e o teste controlado (Área 16).
- **Opções.**
  - **(a) Recomendado:** cadastrar pela UI de inbox do Chatwoot, direto no banco de produção. Nunca por arquivo versionado.
  - (b) Embedded signup, se o app Meta estiver configurado.
- **Quem responde.** Admin Meta.

### D-02 — App Secret da Meta (validação de assinatura)
- **Pergunta.** O App Secret será gravado no `provider_config` do canal (`app_secret`) e/ou em `WHATSAPP_APP_SECRET` (GlobalConfig)?
- **Por que importa.** Em canal `whatsapp_cloud` manual sem secret no próprio canal, `meta_signature_verification_required?` retorna `false`, **mesmo com o secret global configurado** (`whatsapp_controller.rb:45-51`). Nesse caso webhooks sem assinatura são aceitos.
- **O que bloqueia.** Segurança do webhook (RR-S1).
- **Opções.**
  - **(a) Recomendado:** gravar no canal.
  - (b) Só global, mais uma mudança de código para exigir assinatura quando houver secret global.
- **Quem responde.** Admin Meta + Ops.

### D-03 — Templates definitivos
- **Pergunta.** Para cada passo, qual template usar: nome, conteúdo, idioma, categoria e variáveis com a origem de cada valor?
  - Passos: novo_lead 1–4 (ou 1–5, conforme D-06), em_contato 1–5, em_qualificacao 1–7, proposta_enviada 1–3 e `scansolo_proposal_send`.
  - Os templates aprovados no LEXUS podem ser reaproveitados, ou é preciso submeter novos?
- **Por que importa.**
  - O código exige nome exato `scansolo_cadence_<stage>_v1_step<N>` (`cadence_definition.rb:50-52`).
  - O idioma é fixo em `pt_BR` (`native_template_sender.rb:52`).
  - Nenhum parâmetro é enviado (`cadence_due_attempt_job.rb:46-49`), então template com variável falha na Meta.
- **O que bloqueia.** Cadências, envio de proposta e a UI de templates (Área 9).
- **Opções.**
  - (a) Criar os templates na Meta com os nomes da convenção.
  - **(b) Recomendado:** um mapeamento explícito tentativa → template existente, com idioma e parâmetros.
- **Quem responde.** Produto + Admin Meta.

### D-04 — Contrato Make e preço
- **Pergunta.**
  - Qual a URL do cenário e como é a autenticação (Bearer)?
  - Qual o payload de requisição: campos e quais campos de qualificação ele usa?
  - O callback traz o preço autoritativo?
  - Quais variáveis de preço existem?
  - Qual a latência e o timeout esperados?
  - Qual o formato da assinatura `X-Make-Signature`?
  - O preço é calculado no Make ou numa API externa?
- **Por que importa.**
  - `OutboundRequestService` lê as credentials `scan_solo.make.scenario_url`, `scan_solo.make.secret` e `scan_solo.make.inbound_signing_secret` e aceita um `payload` arbitrário (`outbound_request_service.rb:64`).
  - O schema do callback está definido em `callback_verifier.rb:12-56`.
  - Hoje o preço sai do `MockProvider` (1500 BRL).
- **O que bloqueia.** P0-3 (propostas reais) e a regra "a IA nunca inventa preço" com preço determinístico.
- **Opções.**
  - (a) Integrar o Make com o contrato informado.
  - **(b) Recomendado até a resposta:** desabilitar generate/send em produção.
- **Quem responde.** Dono do Make + Produto. Ops provisiona a Rails master key e as credentials.

### D-05 — Política de aprovação de proposta
- **Pergunta.**
  - Toda proposta exige aprovação?
  - Quem pode aprovar e quem pode enviar (admin, dono da oportunidade, qualquer agente)?
  - `require_proposal_approval` deve ficar editável no Agent Center?
- **Por que importa.** O default é `true` (`db/migrate/20260918070002_*:7`; `proposal_version.rb:68-71`), mas o campo não aparece na UI. O envio é voltado ao cliente e não tem confirmação.
- **O que bloqueia.** O desenho da policy (`proposal_policy`) e a UX de Propostas.
- **Opções.** **Recomendado:** aprovação obrigatória por admin ou gestor comercial; envio pelo dono da oportunidade.
- **Quem responde.** Produto.

### D-06 — Abordagem inicial de Novo Lead
- **Pergunta.**
  - Deve haver uma tentativa **imediata** ao criar o lead? O escopo diz "inicial, +2h, +24h, +48h, +96h"; o seed tem só `[2,24,48,96]` (`db/seeds/scansolo_cadence_definitions.rb:7`).
  - Essa tentativa é um template ou texto livre da IA?
- **Por que importa.**
  - Fora da janela de 24h só template funciona (`send_on_whatsapp_service.rb:15-17`).
  - Um lead que escreveu primeiro já está dentro da janela.
- **O que bloqueia.** Seed e versão da cadência novo_lead.
- **Opções.**
  - (a) Template no passo 0.
  - (b) Resposta da IA como primeiro contato, sem passo 0.
  - Recomendado: (b) para lead inbound e (a) para lead importado ou originado fora do WhatsApp.
- **Quem responde.** Produto.

### D-07 — Criação de oportunidade e enroll automático
- **Pergunta.**
  - O que cria uma `PipelineOpportunity`: toda conversa nova da conta, só algumas inboxes, ou uma campanha/CTA?
  - Entrar em novo_lead, em_contato ou em_qualificacao inscreve automaticamente na cadência do estágio?
- **Por que importa.** Hoje nada cria oportunidade, e o enroll automático só existe para proposta_enviada.
- **O que bloqueia.** P0-2 e P0-13.
- **Opções.** **Recomendado:** criar na primeira mensagem inbound em inboxes selecionadas (D-10) e inscrever automaticamente ao entrar em cada estágio.
- **Quem responde.** Produto.

### D-08 — Política de transições
- **Pergunta.**
  - Voltar de estágio é permitido? Pular estágios é permitido?
  - Quem pode mover para negociacao, ganho e perdido?
- **Por que importa.** Hoje qualquer transição não terminal é aceita, e o controller passa `authorized: true` (`pipeline_opportunities_controller.rb:34`).
- **O que bloqueia.** A matriz de transições (P1-22).
- **Quem responde.** Produto/Comercial.

### D-09 — Resposta humana, rajadas e opt-out
- **Pergunta.**
  - Uma resposta manual de agente no inbox deve contar como takeover e pausar a IA e a cadência?
  - Uma atribuição (`assignee`) deve contar?
  - Mensagens em rajada devem ser agrupadas numa resposta? Com qual janela?
  - Como tratar opt-out (palavras-chave, flag no contato)?
- **Por que importa.**
  - `conversation_listener.rb:12` ignora mensagens de saída.
  - Não há lock por conversa.
  - Não existe opt-out alcançável.
- **O que bloqueia.** P0-6 e parte de P0-13.
- **Opções.** **Recomendado:** resposta humana ou atribuição = takeover automático; debounce curto por conversa; opt-out por flag no contato consultada pela cadência.
- **Quem responde.** Produto.

### D-10 — Canais, inboxes e widget
- **Pergunta.**
  - Em quais inboxes a IA responde no go-live: WhatsApp, Website ou também e-mail?
  - Qual a URL e origem do site onde o widget será instalado?
  - Já existe inbox Website na conta 1?
- **Por que importa.** O listener é agnóstico de canal e responde em **qualquer** inbox da conta (`conversation_listener.rb:10-18`).
- **O que bloqueia.** A restrição por inbox e a Área 7.
- **Opções.** **Recomendado:** allowlist explícita de inboxes na configuração do agente.
- **Quem responde.** Produto + Ops.

### D-11 — Escopo de crawl do site
- **Pergunta.**
  - Quais domínios entram na allowlist?
  - Qual a profundidade máxima e o número máximo de páginas?
  - Quais caminhos excluir (admin, login, carrinho)?
  - O crawl respeita robots.txt?
  - O reindex é agendado ou só manual?
- **O que bloqueia.** Fonte URL/site (Área 6).
- **Quem responde.** Produto.

### D-12 — Tecnologia do crawler
- **Pergunta.** Construir um crawler OSS sobre `lib/safe_fetch.rb` + `ssrf_filter` + `reverse_markdown`, ou usar o gem `firecrawl-sdk` (já em `Gemfile:215`), que exige uma conta e chave Firecrawl?
- **Por que importa.** `enterprise/app/services/page_crawler_service.rb` não pode ser usado: a licença é enterprise, não há proteção SSRF e existe a regra de não depender do enterprise.
- **Opções.** **Recomendado:** SafeFetch próprio, pelo controle de SSRF sem dependência paga.
- **Quem responde.** Dev + Produto (custo).

### D-13 — Suporte a PDF
- **Pergunta.** PDFs enviados precisam ser processados? É aceitável adicionar um gem (ex.: `pdf-reader`), ou o admin cola o texto?
- **Por que importa.** Hoje o arquivo é anexado e ignorado (`ingestion_service.rb:20`), e não há parser de PDF no OSS.
- **Opções.**
  - (a) Adicionar o gem.
  - (b) Bloquear o upload até existir suporte.
  - Recomendado: (a), ou (b) se o prazo for curto.
- **Quem responde.** Produto + Dev.

### D-14 — Fonte e mapeamento LEXUS
- **Pergunta.**
  - Como o LEXUS será acessado: API, dump do banco ou CSV?
  - Qual o volume?
  - Qual o mapeamento de campos para contato, conversa, oportunidade (estágio), cadência e proposta?
  - Qual a chave de deduplicação (telefone E.164?)?
  - Quem aprova o gate do dry-run?
- **Por que importa.** `SCANSOLO_LEXUS_CUTOVER_DESIGN.md:292-314` define categorias, mas "none of that script exists yet".
- **O que bloqueia.** Área 14.
- **Quem responde.** Dono do LEXUS + Dev.

### D-15 — Usuários Comercial e papéis
- **Pergunta.**
  - Qual a lista de usuários (nome e e-mail) e o time "Comercial"?
  - Quem é administrador e quem é agente?
  - Quem pode editar e publicar o agente e a base de conhecimento?
- **Por que importa.** Hoje `AiAgentConfigPolicy` e `KnowledgeSourcePolicy` liberam tudo para qualquer agente.
- **O que bloqueia.** Área 17 e as policies (P1-3).
- **Opções.** **Recomendado:** publish e knowledge só para administradores.
- **Quem responde.** Produto/Gestão.

### D-16 — SMTP
- **Pergunta.** Qual o host, porta, usuário, remetente e domínio SPF/DKIM do SMTP? As variáveis SMTP ficam no `.env` da VPS.
- **Por que importa.** Convites, confirmação e recuperação de senha dos usuários do Chatwoot dependem de SMTP.
- **O que bloqueia.** Onboarding do time Comercial.
- **Quem responde.** Ops.

### D-17 — Precedência Captain × ScanSolo
- **Pergunta.** Algum inbox da conta 1 terá um assistente Captain ativo? Se tiver, qual dos dois responde?
- **Por que importa.** O Captain responde em conversas `pending` de inbox com `captain_active?` (`enterprise/app/services/enterprise/message_templates/hook_execution_service.rb:11-14`). O ScanSolo não verifica o Captain.
- **O que bloqueia.** P0-7.
- **Opções.** **Recomendado:** o ScanSolo tem precedência e não roda em inbox com Captain ativo, ou o Captain fica desativado na conta 1. Nos dois casos, documentar.
- **Quem responde.** Produto + Dev.

### D-18 — Campos técnicos visíveis
- **Pergunta.** Correlation ids, JSON de evidência, `sourceId`, `subjectType #id` e enums crus devem ser visíveis a todos, só a admins, ou a ninguém?
- **Evidência.** `Executions.vue:95-98,165-170`, `TurnEvidenceViewer.vue:123-154`, `KnowledgeCenter.vue:255-256`, `KanbanBoard.vue:93`.
- **Opções.** **Recomendado:** esconder para agentes e mostrar numa seção "detalhes técnicos" só para admins.
- **Quem responde.** Produto.

### D-19 — Estratégia de locale
- **Pergunta.** Reescrever `en/scansolo.json` em inglês e criar `pt_BR/scansolo.json` com o português atual, ou manter o ScanSolo só em português e usar `en` como portador?
- **Conflito.**
  - O CLAUDE.md diz: "only update `en.yml` and `en.json`; other languages are handled through Crowdin".
  - Hoje `en/scansolo.json` contém português (ex. `:76` "Provedor do modelo") e não existe `pt_BR`.
  - Mover o português para `pt_BR` viola a regra literal; manter no `en` mostra português a usuários com interface em inglês.
- **O que bloqueia.** A correção definitiva de i18n. O bug das chaves cruas (P0-11) independe desta decisão.
- **Opções.**
  - (a) `en` em inglês + `pt_BR` versionado no fork, como exceção documentada à regra do upstream.
  - (b) Manter português em `en` e documentar como decisão do fork.
  - Recomendado: (a), porque o fork não usa Crowdin.
- **Quem responde.** Produto + Dev.

### D-20 — Compose de produção e build
- **Perguntas.**
  - O comando oficial de produção é `-f docker-compose.production.yaml -f docker-compose.scansolo.yaml` (sem o compose de dev)?
  - `POSTGRES_PASSWORD` vem por `${POSTGRES_PASSWORD}` interpolado ou por `env_file` no serviço postgres?
  - A imagem é sempre construída de um clone completo, ou é preciso um build arg `GIT_SHA`?
  - Qual correção manual foi aplicada na VPS (reportado pelo usuário)? É preciso comparar com o Git.
- **Evidência.** `docker-compose.production.yaml:51`; `SCANSOLO_DEPLOYMENT.md:40-41`; `Dockerfile:90`.
- **O que bloqueia.** P0-8, P0-9 e o runbook (Área 22).
- **Opções.** **Recomendado:** production + overlay sem o dev; `${POSTGRES_PASSWORD}` interpolado a partir do `.env`; `ARG GIT_SHA`. Os profiles `reverse-proxy` (Caddy) e `self-hosted-storage` não sobem, porque a VPS usa Nginx no host (reportado pelo usuário).
- **Quem responde.** Ops.

### D-21 — Kill switch e dono único
- **Pergunta.** Qual mecanismo bloqueia **todo** outbound ScanSolo (turno de IA, cadência, envio de proposta) até a troca de dono do webhook Meta? Opções: flag de conta, ENV ou InstallationConfig. Quem aciona o switch?
- **Por que importa.**
  - Hoje `scansolo_enabled` não para cadência nem proposta.
  - `AiAgentConfig#enabled` não para proposta.
  - O cutover depende só da troca manual do webhook (`PRODUCTION_CUTOVER.md:74-92`).
- **O que bloqueia.** P0-14 e o cutover.
- **Opções.** **Recomendado:** um único flag de conta "outbound habilitado", checado no ponto de entrada comum de envio ScanSolo, conforme a regra do CLAUDE.md de aplicar elegibilidade no ponto de entrada compartilhado mais cedo.
- **Quem responde.** Produto + Ops.

### D-22 — Horário de atendimento e limites de resposta
- **Pergunta.**
  - Qual o formato de `service_hours` e de `response_limits`?
  - O que fazer fora do horário: silêncio, mensagem fixa ou handoff?
  - O horário da IA é o mesmo da janela de cadência (09–20 America/Sao_Paulo)?
- **Por que importa.** Hoje os dois campos são strings livres nunca lidas (ver CURRENT_STATE §2.1).
- **Quem responde.** Produto.

### D-23 — Orçamento de custo
- **Pergunta.** Qual o limite mensal de gasto com LLM e embeddings? Qual o limite de chamadas por conta e por minuto em knowledge, reindex e simulador?
- **Por que importa.** A ingestão faz uma chamada de embedding por chunk, sem throttle, e `top_k` não tem limite (`ingestion_service.rb:24-27`, `retrieval_tests_controller.rb:25-27`).
- **O que bloqueia.** P1-19 (rate limits) e alertas.
- **Quem responde.** Produto/Financeiro.
