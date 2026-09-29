# Confirmed input — scansolo-agent-lead-state (slice 1 of 4)

Source: developer description via /plan (2026-09-29), "Documentação Unificada de Ajustes Desejados — Agente e Sistema ScanSOLO".
The developer confirmed the ACs below. They are the source of truth for the SPEC.

## Summary
Estado estruturado do lead compartilhado entre agente e UI, com qualificação orientada a campos faltantes e encerramento claro.

## Acceptance criteria (confirmed)
AC1 Cada oportunidade persiste um resumo estruturado (blocos: Identificação, Serviço, Local, Escopo, Execução, Comercial, Status); cada campo tem status confirmado|inferido|faltante.
AC2 Toda mensagem inbound atualiza o estado ANTES da resposta; correção do cliente substitui o valor vigente e o anterior fica no histórico.
AC3 O agente não pergunta campo já confirmado (validador de saída rejeita/regenera resposta que pergunta campo confirmado).
AC4 Campos são obrigatórios ou complementares; completar os obrigatórios marca QUALIFICAÇÃO CONCLUÍDA, avança a etapa, registra próxima ação e o agente para de qualificar.
AC5 Próxima pergunta vem só dos faltantes (máx. 2 por mensagem); pergunta direta do cliente é respondida primeiro.
AC6 Localização/PDF/links recebidos contam como informação recebida; CNPJ/razão social/endereço extraídos preenchem o estado (inferido até confirmação).
AC7 Intenção do contato (orçamento, avaliação técnica, convite para cotação, envio de documentos, dúvida, verificar capacidade, localizar rede, visita, acompanhar proposta, outro) é classificada e muda o roteiro junto com a etapa.
AC8 Ação já pedida/autorizada não gera nova confirmação; resumo completo só em mudança de etapa, handoff, encaminhamento, risco de interpretação ou fechamento da qualificação.
AC9 Saída da qualificação ∈ {proposta, avaliação técnica, solicitar documentos, atendimento humano, aguardar cliente}, registrada como próxima ação.

## Out of scope for this slice (planned later as separate /plan runs)
- Slice 2 scansolo-proposal-request-e2e (§12–15, 34–37: internal proposal e-mail, agent e-mail identity, Make end-to-end, failure handling)
- Slice 3 scansolo-operator-console-ux (§17–23, 29–33: menu, Kanban, badges, handoff modal)
- Slice 4 scansolo-followup-reliability (§24–28)
- §16 RFQ form, §38 domain migration (runbook), §39.2 real-lead manual validation
This slice only exposes state (fields, statuses, next action, stage) through the backend/API for later UI consumption. It builds no new UI beyond what the ACs need.

## Key excerpts from the description (for context)
Fields (§4):
- Identificação: contato, empresa, cargo, CNPJ, telefone, e-mail principal, e-mails em cópia.
- Serviço: tipo de serviço, objetivo, tecnologia, interferências buscadas.
- Local: cliente/local final, cidade, UF, endereço, bairro, link.
- Escopo: área, metragem, quantidade de pontos, profundidade de investigação, profundidade da intervenção, superfície, observações técnicas.
- Execução: data desejada, prazo, diárias, integração, tempo de integração, restrições de acesso, documentações necessárias.
- Comercial: prazo para proposta, e-mail para envio, cópias, condições especiais.
- Status: etapa atual, dados confirmados, dados faltantes, próxima ação, responsável, última interação, próximo follow-up.
Stages (§3.13): Novo lead, Em contato, Em qualificação, Qualificado, Avaliação técnica, Proposta em elaboração, Proposta enviada, Negociação, Aguardando pagamento, Fechado, Perdido. The agent's behavior depends on the stage.
Qualification flow (§9): 1) entender demanda (o que, onde, objetivo); 2) dimensionar (área, metragem, profundidade, superfície, pontos, condições técnicas); 3) prazo (data, urgência, integração, acesso); 4) dados comerciais (empresa, CNPJ, contato, e-mail); 5) consolidar (resumo curto); 6) encaminhar.
Confirmed vs inferred vs missing (§6): an inference is never treated as a fact.
Language (§3.7): avoid repeating "Perfeito", "Já entendi", "Fazemos sim", or the client's name in every message.
Correction example (§3.11): "integração de uma diária" → corrected to "integração de 30 minutos no mesmo dia"; the new value becomes the current one immediately.
Core agent rules (§40): never ask what was already answered; answer the client first; update state after every message; ask only what is missing; required vs complementary; honor corrections; read received documents and links; recognize the end of qualification; advance the stage automatically; no successive confirmations; no rigid form; adapt to the objective; record the next action; never make commitments the system cannot keep; never tell the lead about a technical failure.
Target loop (§42): message → interpret → update state → record data → identify what is missing → reply → ask only the next relevant question → update stage → run the next action.

## Existing related work
.spec/features/scansolo-agent-qualification-continuity/ (implemented: ScanSolo::Qualification::FieldResolver, fixed prompt rules, 6 consumers migrated). This slice must extend that work, not duplicate it.
