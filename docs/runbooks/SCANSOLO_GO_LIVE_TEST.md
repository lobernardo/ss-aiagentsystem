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

Reservado para a Phase 6 (checkpoints humanos de go-live).
