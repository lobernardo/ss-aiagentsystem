# Input — Proposta com aprovação explícita, entrega por e-mail e destrave do "Assumir conversa"

Data: 2026-10-07. Base: branch `feat/scansolo-operacao-centralizada` (Phases 1–15 concluídas; 16–20 pendentes).
Feature anterior: `.spec/features/scansolo-operacao-centralizada/` (SPEC v1.3). Esta feature **altera** RF-28, RF-29, RF-30 e RF-55 daquele SPEC.

## 1. Fluxo funcional oficial

1. Lead entra pelo WhatsApp.
2. Agente atende e qualifica.
3. Agente coleta todos os dados necessários do serviço.
4. Sistema cria a solicitação de orçamento.
5. Sistema envia e-mail para comercial@scansolo.com.br.
6. Luciano responde esse e-mail com dados complementares e valores (bloco CT-04).
7. Sistema captura a resposta e correlaciona com a solicitação correta.
8. Automação (Make) gera a proposta no template oficial, personalizada para o lead.
9. A proposta gerada volta para Luciano para aprovação.
10. Luciano aprova explicitamente.
11. Após a aprovação, o sistema envia a proposta ao lead pela inbox de e-mail do agente.
12. comercial@scansolo.com.br vai em cópia.
13. Após envio confirmado, a oportunidade muda para "Proposta enviada".
14. O sistema monitora resposta do lead por WhatsApp e por e-mail.
15. Havendo resposta, atualiza a negociação e interrompe follow-ups incompatíveis.
16. Sem resposta, a cadência assume os follow-ups.
17. Se Luciano quiser assumir a conversa, usa o usuário humano operacional existente no Chatwoot.

## 2. Regras rígidas

- Resposta do Luciano por e-mail NUNCA é aprovação automática.
- Aprovação explícita e idempotente; proposta só é enviada após aprovação.
- Envio confirmado é o gatilho para mover o pipeline para `proposta_enviada`.
- Resposta do lead por WhatsApp ou e-mail correlacionada à oportunidade correta.
- Make gera/transforma o documento, mas não é fonte da verdade; Rails/Chatwoot é a fonte operacional.
- Nenhuma URL, segredo, token ou tenant escolhido pelo modelo.
- Efeitos colaterais idempotentes; retries e falhas auditáveis.

## 3. Decisões do desenvolvedor (2026-10-07)

- D1 Aprovação: botão Aprovar/Rejeitar na tela ScanSolo de Propostas. Luciano é notificado por e-mail na thread do orçamento com o PDF anexo e link para a tela. Transição idempotente e auditada, feita pelo usuário humano dele.
- D2 Entrega: PDF por e-mail pela inbox de e-mail do agente para o e-mail do lead, com `comercial@scansolo.com.br` (= `quote_recipient_email`) em CC, + aviso curto por WhatsApp ("proposta enviada para seu e-mail") sem PDF.
- D3 Sem e-mail do lead: aprovação/entrega fica bloqueada com aviso "falta e-mail do lead"; humano preenche na tela do lead. NÃO altera o agente de IA.
- D4 Rejeição: Luciano rejeita com motivo e responde um novo bloco CT-04 na mesma thread → nova ProposalVersion (passa a haver N versões por solicitação; apenas uma ativa).

## 4. Estado atual relevante (verificado no código)

- AS IS: quote request automático (`quote/request_service.rb`), e-mail ao comercial pela inbox nativa, reply por In-Reply-To (`quote/reply_processor.rb`), parser determinístico CT-04, geração via Make CT-05/CT-06 (`proposal/generate_service.rb`, `make_provider.rb`, `make/*`, webhook HMAC), entrega WhatsApp com PDF (`proposal/delivery_service.rb`), confirmação via `messaging/delivery_reconciler.rb` → `proposal/success_handler.rb` → `proposta_enviada` + cadência + follow-up, handoff (`handoff/*`).
- GAP: sem estado de aprovação no fluxo automático (`DeliveryService` envia logo após o callback); `ApproveService` legado sem auditoria; sem entrega por e-mail/CC; e-mail do lead não correlacionado à oportunidade (vira outra oportunidade ou QuoteReply `unmatched`); `proposal_versions.quote_request_id` único (impede nova versão); resposta cancela só 1 tentativa de cadência.
- Robustez (incluir): `/send` legado aceita versão já `sent` e duplica envio via Make; retry do QuoteRequestJob não reenvia se `deliver!` falhou após commit; falhas de geração (callback/transporte) e callbacks rejeitados sem AuditEvent; `total_value` do callback não conferido com o `commercial.total_value` do pedido; notificação de negociação não idempotente; `make_requests.idempotency_key` sem índice único.

## 5. Contrato Rails ↔ Make

- Manter CT-05/CT-06 (asyncapi da feature anterior). Make só gera documento (`proposal.generate`); não envia e-mail nem escolhe destinatário/URL/tenant.
- Rails rejeita e audita callback com `total_value` diferente do pedido.
- Opcional compatível: `artifact_sha256`, `template_version` no callback de sucesso.
- `proposal.send` sai do fluxo; callbacks históricos continuam aceitos; `/send` legado bloqueado para versões `sent` (ou removido pela Phase 20).

## 6. Make (operador — fases humanas, fora do ralph)

- Phase 16 (T36) deve ser ampliada: a pasta `scanSolo` (247121, team 701134) tem 8 cenários; o T36 lista 6. Incluir 5325058 `Aprovacao_envia_proposta` e 5237984 `Proposta_automatizada`, e exportar a estrutura (sem valores) dos data stores `ScanSOLO_Config` (158313) e `ScanSOLO_Proposta_Map` (158314).
- Ativos hoje: 6177829 `Aprovacao_Gate_Processor` (sem auth), 6019491 `CRM_Agente_Proposta`, 6036802 `Lexus_ScanSolo_Proposta_v2`. Inativos: 6406463 Entrada, 6177833, 5497443, 5325058, 5237984.
- Phase 17: T37 desativa legados (nunca apagar); T38 adapta a Entrada (sem e-mail/envio ao cliente) — continua válido.
- Ordem: Entrada só é ativada (HG-03) depois do deploy do Rails com aprovação; caso contrário o RF-29 atual entrega sem aprovação.

## 7. Ajuste de UI — "Assumir conversa" trava a navegação

Causa provável (ScanSolo, não upstream): `app/javascript/dashboard/components-next/conversation/HandoffControlBanner.vue:177-213` renderiza o modal de motivo como `div fixed inset-0` sem z-index/Teleport; fica acima da ChatList e abaixo da Sidebar (z-40) e pode ficar aberto/invisível (takeover implícito não fecha; erro no POST/GET não fecha).

Menor mudança: usar `components-next/dialog/Dialog.vue` (Teleport, z-index, Esc, cancelar); fechar o diálogo quando `controlState` sair de `ai_active` e em erro; botão X/fechar reaproveitando `BackButton`/`backButtonUrl` do `ConversationHeader` (hoje só no layout expandido — `ConversationBox.vue:107`), apenas `router.push` para a lista.

Requisitos: não alterar ownership/assignment; não criar usuário/fluxo paralelo; preservar o takeover nativo; fechar UI ≠ devolver à IA; handoff independente do estado visual.

ACs: AC-UI-01..06 (assumir → humano; trocar de conversa sem menu; X fecha só o painel; fechar não devolve à IA; navegação não altera ownership/assignment/status/estado; vale para conversa em IA e já humana).
Testes: vitest do banner (troca após assumir, fechamento do diálogo em erro e no takeover implícito, fechar não chama handoff); Playwright E2E: IA atendendo → humano assume → abre outra conversa → volta → estado humano correto.

## 8. Restrições fixas (ROADMAP)

- Não mexer na API oficial do WhatsApp nem no agente de IA/treinamento (prompt, base de conhecimento, config publicada).
- Reaproveitar o que existe; seguir AGENTS.md (Tailwind, components-next, i18n só en.json/en.yml + pt_BR do ScanSolo, sem enterprise).
