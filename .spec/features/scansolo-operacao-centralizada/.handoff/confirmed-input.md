# Confirmed input — scansolo-operacao-centralizada (plano completo, não fatiado)

Tier: complete. Confirmado pelo desenvolvedor em 2026-10-01.

**Fontes, em ordem de precedência**
1. Este arquivo (ACs e decisões confirmadas).
2. `.handoff/diretrizes-desenvolvedor.md` (princípios e fluxo ponta a ponta do desenvolvedor).
3. `.spec/inputs/scansolo-objetivo-operacao-centralizada.md` (objetivo original; itens não listados aqui como essenciais são evolução futura).
4. Referências apenas quando compatíveis: `.spec/ROADMAP.md` (tabela "situação atual × objetivo", verificada no código), `.spec/features/scansolo-proposal-request-e2e/` (SPEC v1.0 e `.handoff/confirmed-input.md` com o levantamento Make/Drive). As decisões antigas D1–D5 e Q-01..Q-07 NÃO são fonte de verdade; ver "Decisões anteriores descartadas".

## Princípios (obrigatórios)
- Preservar o agente atual: treinamento, conhecimento/RAG, personalidade, prompts, configuração publicada, WhatsApp oficial, comportamento do atendimento, cadências existentes. Mudanças no agente só mínimas e controladas, quando o novo fluxo exigir (atualizar/consultar estado do lead, reconhecer negociação).
- Chatwoot nativo primeiro (conversas, contatos, inbox, WhatsApp, templates Meta, atribuição, assumir/devolver, status, mensagens, e-mail). Reutilizar componentes ScanSolo. Customizar só com necessidade real. Não duplicar.
- Antes de criar estrutura: existe no Chatwoot? no ScanSolo? serviço extensível? estado existente? endpoint reutilizável? modelo adequado?
- Não redesenhar nem reorganizar o menu ScanSolo; só acrescentar o necessário aos fluxos.
- Sem nova entidade Lead: Contact → Conversation → `ScanSolo::PipelineOpportunity`.

## Acceptance criteria (confirmados)
- **AC1 Origem.** Origem estruturada do lead com valores SITE/WHATSAPP e MANUAL/COMERCIAL (pode ser vazia). Novos leads sempre gravam origem. Históricos recebem SITE/WHATSAPP só com evidência (conversa iniciada por mensagem recebida do cliente); sem evidência → vazio, exibido "Não informada". Origem não altera cadência.
- **AC2 Lead manual.** Ação "Novo lead" no pipeline atual: localizar Contact por telefone/e-mail ou criar (sem duplicar) → criar Conversation no inbox oficial de WhatsApp → criar PipelineOpportunity em `novo_lead`, origem MANUAL/COMERCIAL, responsável quando aplicável → enviar template inicial aprovado da Meta via `ScanSolo::Messaging::NativeTemplateSender`. Depois segue o fluxo natural (resposta do cliente → em_contato → IA qualifica).
- **AC3 Cadência do lead manual (P4).** O template inicial conta como 1º contato; a cadência de Novo Lead continua a partir da próxima tentativa (sem segundo template 2h depois).
- **AC4 Solicitação de orçamento.** Quando os dados obrigatórios (definidos pela configuração existente: `required_qualification_fields` / estado do lead) estiverem confirmados, o sistema envia e-mail de `atendimento.comercial@scansolo.com.br` para `comercial@scansolo.com.br` usando o inbox/canal de e-mail NATIVO do Chatwoot. Conteúdo organizado: identificação do lead/oportunidade, todos os dados coletados e um bloco estruturado de resposta.
- **AC5 Retorno do orçamento (P2, P3).** A resposta do Luciano (reply ao e-mail) chega na mesma conversa de e-mail e é associada inequivocamente à oportunidade (correlação: oportunidade ↔ solicitação ↔ conversa de e-mail ↔ resposta ↔ Proposal/ProposalVersion ↔ MakeRequest). Leitura determinística do bloco estruturado: valor total, prazo/cronograma, escopo/atividades, condições de pagamento (obrigatórios) e observações comerciais (opcional, texto livre). Bloco incompleto/ilegível → não gera proposta e pede correção. Resposta que não casa com nenhuma solicitação → pendente para vínculo manual. Nenhuma interpretação livre por IA dos campos comerciais.
- **AC6 Geração pelo Make.** Resposta validada → solicitar geração reaproveitando `ScanSolo::Proposal::MakeProvider` e `ScanSolo::Make::OutboundRequestService` (correlation_id, ProposalVersion); payload estendido com os dados comerciais do Luciano além da qualificação. Número da proposta e validade gerados pelo sistema/Make. Proposta só "gerada" após callback assinado válido.
- **AC7 Sem segunda aprovação (P1).** A resposta validada do Luciano é a aprovação comercial; após a geração, a proposta segue para envio sem gate adicional (manter outro gate só se houver necessidade técnica relevante, justificada no SPEC).
- **AC8 Entrega ao lead.** Após callback de geração: registrar artifact/dados; enviar a proposta ao lead pelo WhatsApp (mecanismo nativo de template; PDF preferencialmente como documento no cabeçalho, suporte nativo existente); `sent` somente com sucesso real do envio (aceite do WhatsApp); mover para `proposta_enviada`; enviar mensagem padrão de acompanhamento (conteúdo a definir); matricular na cadência de Proposta Enviada (existente). Geração ≠ entrega.
- **AC9 Pós-proposta.** Agente segue ativo e responde dúvidas dentro dos limites atuais; regras e cadência de Proposta Enviada seguem.
- **AC10 Negociação (P5).** Pedido de negociação (preço, desconto, condição comercial, prazo comercial, pagamento, decisão comercial humana): agente não negocia; responde equivalente a "Vou verificar isso com nosso comercial. Só um momento."; oportunidade → `negociacao`; IA solicita handoff pela máquina de estados existente; Luciano notificado por e-mail com nome, empresa, telefone, oportunidade, link da conversa no Chatwoot, resumo do pedido, dados da proposta, valor vigente e último contexto relevante; quando Luciano tiver usuário no Chatwoot, a conversa é atribuída a ele (atribuição/handoff nativos); sem usuário, só o e-mail (não bloqueia). IA não responde enquanto humano no controle. Notificação via interface substituível/complementável por outro canal sem mudar a lógica central.
- **AC11 Cadência para em resposta (P6).** Qualquer resposta do cliente, mesmo parcial, interrompe a tentativa pendente; o agente processa o que foi informado e identifica o que falta; a automação só volta a atuar diante de nova ausência de resposta. Corrige comportamento, não altera definições de cadência.
- **AC12 Visibilidade mínima (sem redesenho).** Card atual do Kanban, enxuto: acrescenta origem (SITE/COMERCIAL), empresa ou contato, serviço, cidade/UF quando houver, "sem interação há X dias", status do orçamento/proposta e indicador de atendimento humano; o card abre a tela do lead já existente (`OpportunityDetail`), que passa a mostrar dados coletados/faltantes e status do orçamento e da proposta. Classificação `confirmado/inferido/faltante` mantida internamente (já implementada); tela simplifica (coletado / faltante / a confirmar).
- **AC13 Handoff.** Preservar estados `ai_active, handoff_requested, awaiting_human, human_active, paused, closed`; sem novo mecanismo; tomada humana pelo fluxo nativo + estados ScanSolo.

## Fatos verificados no código (2026-10-01)
- E-mail nativo: `Message after_create_commit` → `SendReplyJob` → `Email::SendOnEmailService` → `ConversationReplyMailer` (SMTP por inbox; From = e-mail do canal; Message-ID `<conversation/{uuid}/messages/{id}@domain>`; To = `content_attributes[:to_emails]` ou `contact.email`; Subject = `additional_attributes['mail_subject']`). Respostas: IMAP (`Imap::ImapMailbox`, polling 1 min) e ActionMailbox (`ReplyMailbox`, `Mailbox::ConversationFinder`) casam por `In-Reply-To`/`References`/reply+uuid; sem casamento → conversa nova. Criação programática: ContactInbox de e-mail exige contato com e-mail; `conversation.messages.create!(message_type: :outgoing)` dispara o envio.
- Elegibilidade ScanSolo não olha tipo de canal (`app/services/scan_solo/eligibility.rb:9-18`); inbox fora de `allowed_inbox_ids` → listener ignora (`conversation_listener.rb:33`). O inbox de e-mail deve ficar fora da allowlist.
- Lead manual: `PipelineOpportunity after_create` cria LeadState; `OpportunityBootstrapService` usa `create_or_find_by!` por `conversation_id` (sem duplicar); 1ª mensagem do cliente → `InboundMessageTransitionRule` novo_lead→em_contato + cadência em_contato. `StageEntryEnroller` não roda pelo model. Cadência novo_lead offsets `[2, 24, 48, 96]` h a partir da matrícula; templates `scansolo_cadence_novo_lead_v1_step{n}`; matrícula idempotente.
- `NativeTemplateSender.call(conversation:, template_reference:, origin:, template_params:, actor:)`; `TemplateResolver` por (stage, step) ou convenção; params permitidos `contact_name, contact_first_name, agent_name, stage_label, static`; resolver só gera `body` (header de documento suportado pelo nativo em `whatsapp/template_processor_service.rb:52-76`, não usado).
- IA só move para `em_qualificacao`/`qualificado`; `negociacao` é protegida (`stage_transition_service.rb:13,66-71`). `human_handoff` → `HandoffService` (nota privada + `awaiting_human`, pausa cadências), sem notificação nem atribuição. Não há intent/sinal de negociação.
- Proposta hoje: `CallbackHandler.apply_successful_send!` envia template `scansolo_proposal_send` com `artifact_url` só em `fallback_content`; `DeliveryReconciler` marca `sent` com aceite do WhatsApp; `SuccessHandler` → `proposta_enviada` + cadência pós-proposta. `require_proposal_approval` default true. Retry e dead letter em `RetryPolicy`.
- Make atual (cenário canônico `ScanSOLO_Proposta_Entrada`, inativo) gera rascunho e manda e-mail ao comercial com Form de aprovação; o `Aprovacao_Gate_Processor` aplica dados do Form. Ambos precisam ser adaptados ao novo fluxo.

## Decisões anteriores descartadas (conflito com este plano)
- Gate do Make + Form "Aprovação_Orçamento" como meio de o comercial completar dados → substituído pela resposta por e-mail (AC5).
- E-mail com PDF ao cliente pelo Make e remetente/cópias para o cliente (D3/D4) → entrega ao lead é pelo WhatsApp (AC8).
- Geração automática ao concluir a qualificação (D1) → na conclusão dispara a solicitação de orçamento (AC4); a geração é disparada pela resposta validada (AC6).
- E-mail do lead obrigatório (RF-05 antigo) → não necessário.
- Q-01..Q-07 → sem efeito, exceto: desativar cenários Make legados/quebrados (ex.: `Lexus_ScanSolo_Proposta_v2` com `guid()` inválido) segue recomendado.

## Evolução futura (fora desta versão)
Lista "Leads", tarefas operacionais, relatórios/indicadores (origem já preparada), editor de cadências, cadências novas sem regra operacional, campos por tipo de serviço, lembrete/SLA de resposta do Luciano, outro canal de notificação, reorganização do menu, fotos/KMZ/OCR na proposta, migração de domínio (§38, runbook).

## Gates humanos / dependências externas
- Inbox de e-mail `atendimento.comercial@scansolo.com.br` configurado no Chatwoot (IMAP + SMTP), fora da allowlist da IA.
- Templates Meta aprovados: abordagem inicial (lead manual), proposta com PDF, acompanhamento pós-proposta (texto a definir).
- Usuário do Luciano no Chatwoot (opcional; não bloqueia).
- Cenário Make ajustado para receber os dados do orçamento e devolver a proposta completa (alterações no Make com backup de blueprint e aprovação do desenvolvedor; nada ativado antes das credenciais HG-03 no Rails).
