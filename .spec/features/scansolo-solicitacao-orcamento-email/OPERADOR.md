# Operador — scansolo-solicitacao-orcamento-email

Passos manuais, fora do `scripts/ralph.sh` (o ralph executa só o `PHASES.md`, fases 1–10). Nada aqui roda sem autorização explícita do desenvolvedor para deploy e para o envio de teste.

## T21 — Nome de exibição do inbox de orçamento (RF-15, RF-21)

Origem: Phase 11 do PLAN, movida do `PHASES.md` em 2026-10-10 para o ralph não executar uma tarefa operacional.

- No inbox publicado como `quote_inbox_id` (`atendimento.comercial@scansolo.com.br`): `business_name` = `Atendimento Comercial ScanSolo` e `sender_name_type` = `professional`. Configuração do inbox, nenhum e-mail enviado.
- Depois do deploy: conferir `published.quote_email_validation_mode = true` na configuração do agente.
- Aceite: `GET /api/v1/accounts/<id>/inboxes/<quote_inbox_id>` mostra os 2 valores; `GET .../scan_solo/ai_agent_config` mostra a flag `true`; linha datada no `.spec/features/scansolo-operacao-centralizada/make/REGISTRO.md`.

## Envio de teste (decisão do desenvolvedor, 2026-10-10)

O e-mail de teste vai para o **próprio e-mail do agente** (`atendimento.comercial@scansolo.com.br`), não para `comercial@`. O desenvolvedor avalia o formato antes de liberar para o Luciano.

1. Pré-requisito: fases 1–10 concluídas, deploy autorizado e feito, T21 feito.
2. Na configuração publicada (OC/RF-54), trocar o destinatário comercial para `atendimento.comercial@scansolo.com.br`. Registrar o valor anterior (`comercial@scansolo.com.br`) para rollback.
3. Disparar 1 qualificação de teste com próxima ação `proposta` (lead de teste, sem cliente real), cobrindo: cidade/UF, 1 link de mapa, 1 anexo pequeno e ao menos 1 pendência.
4. Conferir: e-mail recebido na caixa do agente com o assunto `Solicitação de orçamento | … | … | …`, remetente "Atendimento Comercial ScanSolo", parágrafo do modo validação, seções na ordem do CT-01, bloco CT-04 no fim, anexo presente; auditoria `quote_request.sent`.
5. Loop: a cópia que volta pelo IMAP tem o mesmo Message-ID salvo em `messages.source_id` (`app/services/email/send_on_email_service.rb:13`) e é descartada por `email_already_present?` (`app/services/imap/base_fetch_email_service.rb:40-43`), então não vira resposta do comercial. Se mesmo assim aparecer uma mensagem `incoming` na conversa da solicitação, parar e verificar antes de qualquer outro passo.
6. Não responder ao e-mail de teste com o bloco preenchido (isso geraria proposta).
7. Depois da avaliação: voltar o destinatário para `comercial@scansolo.com.br` só com o OK do desenvolvedor; registrar no `REGISTRO.md`.
8. Liberar para o Luciano (com o modo validação ligado). Desligar o modo validação quando ele aprovar o formato.
