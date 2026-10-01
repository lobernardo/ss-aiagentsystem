# Clarifier questions — round 1 (pending developer answers)

Source: clarifier analyze over SPEC.md v1.0 (2026-09-30). Recommended option first.

- Q-01 [Contradição] RF-13 × RF-11/RetryPolicy/CT-02 — retry reusa o mesmo `pv_{id}` com correlation_id novo. (a) idempotência no Entrada por idempotency_key/correlation; pv_ repetido com correlation novo atualiza o Map e retoma o passo que falhou; (b) idempotência por pv_ reemitindo o último callback com o correlation novo; (c) retry cria versão nova.
- Q-02 [M1] RF-05a/RF-01/RF-05 — e-mail antes da geração. (a) e-mail obrigatório efetivo na conclusão só para intenções que levam a `proposta`; (b) conclusão sem e-mail + 2º gatilho quando o e-mail chega; (c) só configurar `email` em required_qualification_fields.
- Q-03 [M3 + lacuna] RF-11a/RF-06 — versões presas. (a) sem limite para `generating`; `send` em andamento > N horas → failed/provider_unavailable (definir N); (b) limite para os dois estados; (c) manual.
- Q-04 [M4] RF-23 — `proposal_generate` da IA com proposta existente. (a) no-op/rejeita; (b) remover a ação do modelo; (c) manter como hoje.
- Q-05 [M5] RF-08 — link do aviso WhatsApp. (a) callback `send` traz URL do PDF exportado, compartilhado "qualquer pessoa com o link"; (b) artifact_url do generate; (c) aviso sem link. + O template `scansolo_proposal_send` aprovado tem variável de link?
- Q-06 [M2] RF-11b — sent_at/transport_message_id/valid_until. (a) não persistir (já em MakeCallback.payload); (b) colunas; (c) só valid_until.
- Q-07 [Lacuna] RF-04/RF-10/CT-01 — formato de emails_copia_proposta. (a) string separada por vírgula; (b) array.

Also pending: tier upgrade standard → complete (26 RF).
