# ScanSolo — Roteiro de teste controlado de go-live

Teste único, em produção, com um contato de teste controlado pela equipe,
depois do deploy (`docs/architecture/SCANSOLO_DEPLOYMENT.md`, passo 8 verde) e
com o inbox WhatsApp de teste na allowlist publicada do Agent Center.

Convenções:

- `<account_id>`, `<conversation_id>`, `<contact_phone>` e `<correlation_id>`
  são preenchidos pelo operador durante o teste.
- `API` = `https://<host>/api/v1/accounts/<account_id>/scan_solo`, chamada com o
  header `api_access_token` de um administrador.
- `RUNNER` = `docker compose -f docker-compose.production.yaml -f docker-compose.scansolo.yaml exec rails bundle exec rails runner`.
- Cada critério tem um resultado binário. Qualquer `Passa se` falso reprova o
  go-live: desligue `scansolo_enabled` na conta (kill switch) e registre o
  critério reprovado.

## Critérios

### 1. Mensagem real chega

- **Ação**: do celular de teste, enviar "Olá, quero um orçamento" para o número WhatsApp do inbox allowlisted.
- **Evidência**: tela da conversa no dashboard; `RUNNER "p Contact.find_by(phone_number: '<contact_phone>').conversations.last.messages.incoming.last&.content"`.
- **Passa se**: a mensagem aparece na conversa em até 1 minuto e o runner imprime o texto enviado.

### 2. Exatamente um turno

- **Ação**: aguardar 2 minutos após o critério 1 sem enviar outra mensagem.
- **Evidência**: `RUNNER "p ScanSolo::AiTurn.where(conversation_id: <conversation_id>).pluck(:correlation_id, :invocation_status)"`; `GET API/ai_turns/<correlation_id>`.
- **Passa se**: o runner lista um único turno com `invocation_status` `succeeded` (anote o `<correlation_id>`) e a API o retorna.

### 3. Exatamente uma resposta

- **Ação**: conferir a conversa no celular de teste e no dashboard.
- **Evidência**: `RUNNER "p Conversation.find(<conversation_id>).messages.outgoing.where(private: false).count"`; campo `response_message_id` do turno em `GET API/ai_turns/<correlation_id>`.
- **Passa se**: o runner imprime `1`, o celular recebeu uma única resposta e `response_message_id` é essa mensagem.

### 4. RAG usado

- **Ação**: abrir a evidência do turno no Agent Center (visualizador de evidências do turno).
- **Evidência**: `GET API/ai_turns/<correlation_id>` → `knowledge_evidence`.
- **Passa se**: `knowledge_evidence` não é vazio e cita ao menos uma fonte publicada da base de conhecimento.

### 5. Oportunidade criada

- **Ação**: abrir o Kanban do pipeline ScanSolo.
- **Evidência**: `RUNNER "p ScanSolo::PipelineOpportunity.where(conversation_id: <conversation_id>).count"`; card no Kanban.
- **Passa se**: o runner imprime `1` e o card do contato de teste aparece no Kanban.

### 6. Estágio correto

- **Ação**: enviar uma segunda mensagem do celular de teste ("Pode me explicar melhor?") e aguardar a resposta.
- **Evidência**: `RUNNER "p ScanSolo::PipelineOpportunity.find_by(conversation_id: <conversation_id>).stage"`; histórico de estágio no detalhe da oportunidade.
- **Passa se**: após a primeira mensagem o estágio era `novo_lead` e após a segunda é `em_contato`.

### 7. Cadência coerente

- **Ação**: abrir a tela de follow-ups da oportunidade de teste.
- **Evidência**: `RUNNER "p ScanSolo::PipelineOpportunity.find_by(conversation_id: <conversation_id>).cadence_enrollments.map { |e| [e.cadence_definition.stage, e.status] }"`.
- **Passa se**: existe exatamente uma inscrição `active`, na cadência do estágio atual (`em_contato`), e a de `novo_lead` está `cancelled`.

### 8. Resposta humana pausa a IA

- **Ação**: um agente responde manualmente na conversa pelo dashboard (mensagem não privada); em seguida o celular de teste envia "Ainda está aí?".
- **Evidência**: `GET API/conversations/<conversation_id>/control_state`; banner de controle da conversa; `RUNNER "p ScanSolo::AiTurn.where(conversation_id: <conversation_id>).last.invocation_status"`.
- **Passa se**: o estado é `human_active` sem recarregar a página, a inscrição da cadência está `paused` e nenhuma resposta de IA é enviada para "Ainda está aí?".

### 9. Devolver à IA funciona

- **Ação**: no banner da conversa, clicar em devolver à IA; depois o celular de teste envia "Voltei".
- **Evidência**: `GET API/conversations/<conversation_id>/control_state`; tela da conversa.
- **Passa se**: o estado é `ai_active`, a cadência volta a `active` e "Voltei" recebe exatamente uma resposta da IA.

### 10. Nenhuma proposta mock

- **Ação**: consultar o status operacional e as versões de proposta da conta.
- **Evidência**: `GET API/status` → `proposal_integration`; `RUNNER "p ScanSolo::ProposalVersion.where(value: 1500.0).or(ScanSolo::ProposalVersion.where('artifact_url LIKE ?', '%mock-proposals.scansolo.test%')).count"`.
- **Passa se**: `proposal_integration` é `configured` ou `blocked` (nunca mock) e o runner imprime `0`.

### 11. Logs e correlation id

- **Ação**: buscar nos logs do Rails e do Sidekiq o correlation id do turno do critério 2.
- **Evidência**: `docker compose -f docker-compose.production.yaml -f docker-compose.scansolo.yaml logs rails sidekiq --since 30m | grep <correlation_id>`; `GET API/ai_turns/<correlation_id>`.
- **Passa se**: o correlation id aparece sem redação nos logs, a API retorna o turno por esse id e nenhuma chave `sk-...` aparece nos logs.

### 12. Nenhum envio duplicado

- **Ação**: ao final do teste, comparar as mensagens recebidas no celular de teste com as mensagens enviadas pela conversa.
- **Evidência**: `RUNNER "p Conversation.find(<conversation_id>).messages.outgoing.where(private: false).group(:content).having('count(*) > 1').count"`; histórico do celular de teste.
- **Passa se**: o runner imprime `{}` e o celular não mostra nenhuma mensagem repetida.

## Gates humanos

Checkpoints externos (HG-01..HG-11 da SPEC) executados por humanos fora do
repositório. Nenhum agente executa a ação protegida; cada gate só libera a
própria ativação, nunca o código ou os specs das demais fases.

Convenções:

- `STATUS` = `GET API/status` (CT-07); os campos citados como `status.<campo>`
  são chaves da resposta JSON.
- `SMOKE` = `docker compose -f docker-compose.production.yaml -f docker-compose.scansolo.yaml exec rails bundle exec rails "scansolo:smoke[<account_id>]"`.
- A **Verificação** é binária; o gate só é assinado quando ela passa.
- **Assinatura**: marque `[x]` e preencha nome e data de quem executou.

### HG-01 — Credenciais Meta no inbox WhatsApp nativo

- **Dono**: Admin Meta.
- **Ação**: cadastrar as credenciais Meta (phone number id, business account id, token) no inbox WhatsApp nativo e o App Secret no canal, para que o webhook seja validado pela assinatura `X-Hub-Signature-256` do App Secret.
- **Desbloqueia**: tráfego real de WhatsApp e os critérios 1–12 deste roteiro.
- **Verificação**: um webhook assinado da Meta é recebido e aceito (critério 1: a mensagem real chega na conversa); webhooks sem assinatura válida continuam rejeitados.
- **Assinatura**: [ ] Admin Meta — nome: ________ data: ________

### HG-02 — Templates Meta aprovados e mapeados

- **Dono**: Produto + Admin Meta.
- **Ação**: aprovar na Meta os templates finais de cada estágio/passo de cadência e do envio de proposta, sincronizar os templates do inbox e cadastrar os mapeamentos em `PUT API/cadence_templates`.
- **Desbloqueia**: envios reais de cadência e de proposta.
- **Verificação**: `GET API/cadence_templates` (`GET /scan_solo/cadence_templates`) não retorna nenhuma linha com `availability` `blocked` (todas `mapped: true`, `availability: "available"`).
- **Assinatura**: [ ] Produto — nome: ________ data: ________ / [ ] Admin Meta — nome: ________ data: ________

### HG-03 — Integração Make

- **Dono**: Dono do Make + Ops.
- **Ação**: gravar nas Rails credentials as 3 credenciais `scan_solo.make.scenario_url`, `scan_solo.make.secret` e `scan_solo.make.inbound_signing_secret`, instalar a master key na VPS e fechar com o Dono do Make o contrato de payload/preço (CT-05/CT-06), incluindo `requested_by_user_id` nulo em propostas iniciadas pela IA.
- **Decisão de `action`**: o código envia e valida `action` `proposal.generate` / `proposal.send`. Se o cenário Make exigir `generate` / `send`, o payload de saída e o schema do callback mudam juntos antes de assinar este gate. Nomenclatura acordada: ________
- **Desbloqueia**: propostas reais (RF-36) e o critério 10 deste roteiro.
- **Verificação**: `STATUS` → `status.proposal_integration == "configured"`; `SMOKE` imprime `PASS proposal_integration`.
- **Assinatura**: [ ] Dono do Make — nome: ________ data: ________ / [ ] Ops — nome: ________ data: ________

### HG-04 — SMTP da VPS

- **Dono**: Ops.
- **Ação**: preencher `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_DOMAIN` e `MAILER_SENDER_EMAIL` no `.env` da VPS e reiniciar Rails e Sidekiq.
- **Desbloqueia**: convites de usuário e redefinição de senha.
- **Verificação**: um convite de usuário enviado pelo dashboard (Configurações → Agentes) é entregue na caixa de entrada do convidado.
- **Assinatura**: [ ] Ops — nome: ________ data: ________

### HG-05 — Dono único do webhook Meta (LEXUS)

- **Dono**: Dono LEXUS + Ops.
- **Ação**: definir a origem/mapeamento LEXUS e trocar o webhook Meta do número para um único dono automático, seguindo `docs/runbooks/PRODUCTION_CUTOVER.md` ("Single-owner rule" e "Suggested cutover sequence").
- **Desbloqueia**: o cutover do número hoje operado pelo LEXUS (o go-live num número que o LEXUS não opera não depende deste gate).
- **Verificação**: checklist de `docs/runbooks/PRODUCTION_CUTOVER.md` concluído, com o webhook Meta apontando só para o ScanSolo; o kill switch `scansolo_enabled` (desligar a flag na conta) foi testado e interrompe as respostas de IA.
- **Assinatura**: [ ] Dono LEXUS — nome: ________ data: ________ / [ ] Ops — nome: ________ data: ________

### HG-06 — Allowlist de inboxes e Captain inativo

- **Dono**: Produto + Ops.
- **Ação**: definir os inboxes da allowlist no Agent Center, publicar a configuração e confirmar que o Captain (ou qualquer agent bot) está inativo nesses inboxes.
- **Desbloqueia**: qualquer resposta de IA (allowlist vazia = fail closed).
- **Verificação**: `STATUS` → `status.agent.allowed_inbox_ids` não vazio e `status.inbox_conflicts == []`; `SMOKE` imprime `PASS agent_config` e `PASS inbox_conflicts`.
- **Assinatura**: [ ] Produto — nome: ________ data: ________ / [ ] Ops — nome: ________ data: ________

### HG-07 — Usuários e papéis de administrador

- **Dono**: Produto/Gestão.
- **Ação**: definir os usuários comerciais e quais deles são administradores da conta (só administradores publicam/editam conhecimento, templates e o Agent Center).
- **Desbloqueia**: quem pode publicar/editar conhecimento em produção (RF-48).
- **Verificação**: a lista de agentes da conta (Configurações → Agentes) mostra os administradores definidos com papel `administrator` e os demais usuários comerciais com papel `agent`.
- **Assinatura**: [ ] Produto/Gestão — nome: ________ data: ________

### HG-08 — Diff da VPS contra o Git

- **Dono**: Ops.
- **Ação**: antes do deploy, comparar o compose e os nomes do `.env` da VPS com o Git e conferir as tags de imagem em execução — passo 1 de `docs/architecture/SCANSOLO_DEPLOYMENT.md` ("Step 1 — Diff the VPS compose and .env names against Git").
- **Desbloqueia**: a execução do deploy.
- **Verificação**: o passo 1 do runbook passa: nenhuma edição local nos arquivos compose, todo nome ausente do `.env` entendido/preenchido, imagens `postgres` e `redis` em execução iguais às tags de `docker-compose.production.yaml` e a tag anterior registrada para rollback.
- **Assinatura**: [ ] Ops — nome: ________ data: ________

### HG-09 — Chave OpenAI e restart

- **Dono**: Ops.
- **Ação**: gravar a chave OpenAI (`CAPTAIN_OPEN_AI_API_KEY`) e reiniciar Rails e Sidekiq (`docs/architecture/SCANSOLO_DEPLOYMENT.md`, "OpenAI key rotation").
- **Desbloqueia**: turnos reais de IA.
- **Verificação**: `STATUS` → `status.llm_key_configured == true` (`SMOKE` imprime `PASS llm_key_configured`) e um turno `succeeded` no critério 2.
- **Assinatura**: [ ] Ops — nome: ________ data: ________

### HG-10 — Execução e assinatura do go-live

- **Dono**: Produto + Ops.
- **Ação**: com HG-01, HG-02, HG-03, HG-06, HG-08 e HG-09 assinados, executar os 12 critérios deste roteiro na ordem e registrar a evidência de cada um.
- **Desbloqueia**: declarar a produção no ar.
- **Verificação**: os 12 critérios estão marcados "Passa" (todo `Passa se` verdadeiro) e `SMOKE` imprime `ScanSolo smoke passed`. A produção só é declarada no ar com todos os 12 "Passa"; qualquer falha aciona o kill switch `scansolo_enabled` e o gate não é assinado.
- **Assinatura**: [ ] Produto — nome: ________ data: ________ / [ ] Ops — nome: ________ data: ________

### HG-11 — Escopo de PDF e crawler

- **Dono**: Produto + Dev.
- **Ação**: decidir o escopo e a tecnologia de extração de PDF e de crawl de URL/site para a base de conhecimento.
- **Desbloqueia**: RF-47 (P2). Até esta decisão, RF-47 não é implementado e fontes só com anexo ficam `failed` (RF-45).
- **Restrição RF-47**: quando implementado, o conteúdo remoto é buscado somente via `SafeFetch` + `ssrf_filter` (`lib/safe_fetch.rb`), restrito a uma allowlist de domínio definida pelo administrador, e nunca por `enterprise/app/services/page_crawler_service.rb`.
- **Verificação**: decisão registrada (escopo, tecnologia e allowlist de domínio) na SPEC da feature; nenhuma busca remota de PDF/crawler existe fora de `SafeFetch`.
- **Assinatura**: [ ] Produto — nome: ________ data: ________ / [ ] Dev — nome: ________ data: ________
