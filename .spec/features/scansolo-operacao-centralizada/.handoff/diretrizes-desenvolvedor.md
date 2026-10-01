# Diretrizes do desenvolvedor — plano completo (2026-10-01)

Fonte de verdade principal deste plano. Prevalece sobre `.spec/ROADMAP.md`, sobre o SPEC v1.0 de `scansolo-proposal-request-e2e` e sobre decisões anteriores (D1–D5, Q-01..Q-07), que valem só como referência quando compatíveis.

Ordem de leitura: (1) este arquivo; (2) objetivo em `.spec/inputs/scansolo-objetivo-operacao-centralizada.md`; (3) referências.

## Princípios
- Preservar ao máximo arquitetura e comportamento existentes. Agente configurado, treinado e ativo em produção: ajustes incrementais, sem regressões, sem substituir fluxos funcionais.
- Chatwoot nativo como regra (conversas, contatos, inbox, WhatsApp, templates Meta, atribuição, assumir/devolver conversa, status de conversa, mensagens, e-mail quando possível). Só criar componente ScanSolo quando o nativo não existir, não atender a regra, ou houver necessidade específica. Não duplicar.
- Antes de qualquer estrutura nova verificar: existe no Chatwoot? no namespace ScanSolo? serviço extensível? estado existente? endpoint reutilizável? modelo adequado?
- Não redesenhar nem reorganizar o menu ScanSolo; acrescentar só telas/ações/indicadores necessários aos novos fluxos.
- Não afetar: configuração do agente, treinamento, base de conhecimento, prompts, RAG, regras publicadas, comportamento atual do atendimento, cadências existentes. Mudanças mínimas e controladas no agente são permitidas apenas quando o novo fluxo exigir (consultar/atualizar estado do lead, preparar solicitação de orçamento, reconhecer negociação).

## 1. Lead manual
Reaproveitar Contact → Conversation → ScanSolo::PipelineOpportunity (sem entidade Lead paralela).
No cadastro: criar ou localizar Contact (sem duplicar); criar Conversation no inbox oficial de WhatsApp; criar PipelineOpportunity; origem MANUAL/COMERCIAL; responsável quando aplicável; etapa Novo Lead; enviar template inicial aprovado da Meta (abordagem comercial simples: apresentação da ScanSolo e início do atendimento) via `ScanSolo::Messaging::NativeTemplateSender` (`conversation.messages.create!`, envio pelo fluxo nativo; sem HTTP paralelo com Meta). Daí em diante, mesmo fluxo dos leads naturais.
Origem estruturada com pelo menos SITE/WHATSAPP e MANUAL/COMERCIAL (filtros e métricas futuras). Históricos: preencher só com evidência (decisão da revisão anterior).

## 2–3. Handoff
Preservar a máquina de estados existente (ai_active, handoff_requested, awaiting_human, human_active, paused, closed). Não criar outro mecanismo. Tomada humana pelo fluxo nativo + estados ScanSolo; interrompe IA e automações conforme regras já implementadas.

## 5. Qualificação
Agente qualifica normalmente; coleta os dados definidos na configuração/treinamento atuais. Não criar lista nova de campos se já definidos em `required_qualification_fields`, `qualification_playbook`, `custom_attributes` ou estrutura existente. Usar os dados estruturados já coletados. Quando todos os dados necessários para orçamento estiverem confirmados, começa o fluxo de orçamento.

## 6–7. Orçamento humano (Luciano) por e-mail
Lead qualificado → agente verifica dados completos → prepara solicitação de orçamento → e-mail de atendimento.comercial@scansolo.com.br para comercial@scansolo.com.br → Luciano calcula e responde ao e-mail → resposta chega em atendimento.comercial@ → sistema identifica a oportunidade → combina qualificação + orçamento → só então solicita a proposta ao Make.
Correlação inequívoca entre oportunidade, lead, conversa, solicitação enviada, resposta do Luciano, Proposal/ProposalVersion e requisição Make (correlation_id ou identificador robusto).
Verificar primeiro se o inbox/canal nativo de e-mail do Chatwoot atende com segurança; integração própria só com limitação real.
Conteúdo ao Luciano organizado e suficiente: identificação do lead e todos os dados coletados.

## 8. Proposta pelo Make
Reaproveitar `ScanSolo::Proposal::MakeProvider` e `ScanSolo::Make::OutboundRequestService` (correlation_id, payload de ProposalVersion). Estender o contrato para incluir os dados comerciais do Luciano. Make monta a proposta completa e devolve callback assinado; proposta só é "gerada" após callback válido.

## 9. Envio ao lead
Após callback de geração: registrar artifact/dados; enviar a proposta ao lead pelo WhatsApp; registrar sucesso real do envio; mover para Proposta Enviada; enviar mensagem padrão de acompanhamento (a definir); matricular na cadência de Proposta Enviada. Reutilizar ProposalVersion, callbacks, mudança de etapa e NativeTemplateSender. Geração ≠ entrega.

## 10. Pós-proposta
Agente permanece ativo, responde dúvidas dentro dos limites atuais; regras e cadência de Proposta Enviada continuam.

## 11. Negociação
Pedido de negociação (preço, desconto, condição comercial, prazo comercial, pagamento, ou qualquer decisão comercial humana): agente não negocia; responde algo como "Vou verificar isso com nosso comercial. Só um momento."; oportunidade → Negociação; IA solicita handoff; Luciano notificado (inicialmente por e-mail) com: nome, empresa, telefone, oportunidade, link da conversa no Chatwoot, resumo da negociação, dados da proposta, valor vigente, último contexto relevante; Luciano assume no Chatwoot; IA para enquanto humano no controle. Notificação substituível/complementável por outro canal sem mudar a lógica central.

## 13. Fluxo ponta a ponta
Natural: WhatsApp/Site → conversa → oportunidade → IA qualifica.
Manual: comercial cadastra → Contact → Conversation → PipelineOpportunity → template Meta inicial → IA atende → qualifica.
Após qualificação: dados completos → e-mail ao Luciano → precifica → responde → sistema associa ao lead → agrega qualificação + orçamento → Make gera → callback → proposta via WhatsApp → Proposta Enviada → cadência Proposta Enviada.
Negociação: cliente pede → IA avisa → Negociação → notificação ao Luciano → handoff → Luciano assume.

## Da revisão anterior (aceito pelo desenvolvedor)
- Origem histórica só com evidência; vazia = "Não informada".
- Card do Kanban enxuto; detalhes na tela do lead.
- `confirmado/inferido/faltante` já implementado e em uso: mantido internamente; tela simplifica.
- Sem editor de cadências; sem cadências novas sem regra operacional real.
