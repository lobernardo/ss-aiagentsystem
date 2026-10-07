# Clarifier answers — 2026-10-07 (developer)

- Q-01 (M-01): (b) Admin OU o `commercial_user_id` publicado aprova/rejeita; mesma regra para retry/reprocessar (RF-15). Ajustar policy, CT-02/CT-03 (403), UI-01 e HG-F.
- Q-02 (M-02): (a) Novo slot `proposta_aviso_email` via `TemplateMapping`, novo template Meta sem documento aprovado no HG-E; `scansolo_proposal_send` intacto.
- Q-03: (b) Aviso WhatsApp só depois do e-mail confirmado (versão `sent`, disparo no reconciler); retry RF-15 envia o aviso quando o e-mail for confirmado. Ajustar RF-11, RF-12, RF-15, RNF-02.
- Q-04: (a) Só mensagens do e-mail do contato contam como resposta do lead; mensagens de `quote_recipient_email` ou outros remetentes ficam na conversa sem efeito (sem interação, sem cancelar cadência). Ajustar RF-16/RF-18 e AC.
- Q-05: (b) O `retry` existente cobre falhas pré-aprovação: regenera pelo Make (RetryPolicy/dead letter atuais) ou rebaixa o PDF para `artifact_download_failed`/`artifact_checksum_mismatch`. Respostas do Luciano nesses casos continuam `late_reply`. Ajustar RF-15 escopo e RF-03/RF-07 coerentes.
- Q-06 (M-03): (a) Callback com assinatura inválida → 401, sem AuditEvent nem gravação; só log/métrica. RNF-06 inalterado.
- Interpretações confirmadas: "inbox de e-mail do agente" = `quote_inbox_id` publicado; com N versões, a conversa de e-mail da proposta com o lead é reutilizada (1 por oportunidade).
