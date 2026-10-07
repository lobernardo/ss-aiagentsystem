# Confirmed input — scansolo-proposta-aprovacao-email (2026-10-07)

Tier: complete. Description: `.spec/inputs/scansolo-proposta-aprovacao-email.md` (fluxo, regras rígidas, decisões D1–D4, estado atual, contrato, Make, UI).
Feature anterior alterada: `.spec/features/scansolo-operacao-centralizada/SPEC.md` v1.3 (RF-28, RF-29, RF-30, RF-55); contratos CT-05/CT-06 em `.spec/features/scansolo-operacao-centralizada/asyncapi.yaml`.

Summary: proposta com aprovação explícita do Luciano na tela ScanSolo, entrega por e-mail ao lead com comercial@ em CC + aviso WhatsApp, correlação de resposta do lead por e-mail, e destrave da UI do "Assumir conversa".

## Confirmed ACs (developer-confirmed source of truth)

- AC-01 Callback de geração com sucesso deixa a versão em `awaiting_approval`; nada é enviado ao lead e a etapa não muda.
- AC-02 Luciano recebe, na thread do orçamento, e-mail com PDF anexo + link da tela; resposta dele por e-mail nunca muda o status para aprovado.
- AC-03 Botão Aprovar (tela Propostas) é idempotente, auditado, grava usuário; aprovar duas vezes não gera segundo envio. Rejeitar exige motivo e é auditado.
- AC-04 Após rejeição, novo bloco CT-04 na mesma thread gera nova versão; só uma versão ativa por solicitação.
- AC-05 Lead sem e-mail: aprovação/entrega bloqueada com aviso "falta e-mail do lead"; humano preenche na tela do lead e o fluxo prossegue; agente de IA não é alterado.
- AC-06 Após aprovação: e-mail com PDF pela inbox do agente para o lead, `comercial@scansolo.com.br` em CC, + aviso WhatsApp curto sem PDF; ambos idempotentes por versão.
- AC-07 Etapa vai para `proposta_enviada` só com envio de e-mail confirmado (mensagem com `source_id` e não `failed`); falha é auditada e não move a etapa.
- AC-08 Resposta do lead por e-mail na thread da proposta é correlacionada à oportunidade certa (não cria oportunidade nova nem vira `unmatched`), atualiza última interação e interrompe a cadência.
- AC-09 Resposta do lead (WhatsApp ou e-mail) em `proposta_enviada` interrompe todas as tentativas pendentes da cadência, não só a próxima.
- AC-10 Callback com `total_value` diferente do pedido é rejeitado e auditado; falhas de geração (callback/transporte) e callbacks rejeitados geram AuditEvent.
- AC-11 `/send` legado não reenvia versão já `sent` nem envia versão não aprovada; `proposal.send` sai do fluxo.
- AC-12 AC-UI-01..06: após "Assumir conversa" é possível trocar de conversa pela lista; X fecha só o painel; fechar não devolve à IA nem muda assignment/estado; testes vitest + E2E Playwright.
- AC-13 Phase 16 ampliada (8 cenários da pasta `scanSolo` + estrutura dos 2 data stores) e Phase 17 (T37/T38) como fases de operador; ativação da Entrada só após deploy do Rails.
