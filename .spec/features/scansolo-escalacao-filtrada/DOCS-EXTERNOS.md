# Documentos externos — scansolo-escalacao-filtrada (T12)

Checklist para o Leo. Estes arquivos ficam fora deste repositório (`DECISOES.md` e os demais não existem na raiz de `ss-aiagentsystem`), então a edição é manual. Cada item traz o conteúdo a incluir. Referências: `SPEC.md` v1.1, `PLAN.md`, `APROVACAO.md` (DEC-060 e redação aprovada).

Os 6 documentos:

- [ ] 1. `DECISOES.md`
- [ ] 2. `STATUS_ATUAL.md`
- [ ] 3. `claude/FUNCIONAMENTO_ATUAL_*.md`
- [ ] 4. `CHANGELOG.md`
- [ ] 5. `claude/AGENTE_CONFIG_V4.md`
- [ ] 6. `BACKLOG.md`

---

## 1. `DECISOES.md`

Confirmar que a DEC-060 está registrada (aprovada em 16/11/2026, ver `APROVACAO.md`). Conteúdo mínimo:

- **DEC-060 — Escalação filtrada ao Artur: e-mail primeiro, `wa.me` só para quem insiste.**
- Contexto: desde 10/11/2026 o link `wa.me` do comercial saiu 4 vezes, só 1 dentro da regra (Daiane conv. 122, Alexandre conv. 120, Azanis conv. 86, CSI conv. 111; a CSI recebeu o link de novo em resposta a "Ok").
- Decisão: a aplicação, e não o LLM, decide a entrega do link. Elegível só quando:
  - etapa `qualificado`, `proposta_enviada` ou `negociacao`;
  - pedido de orçamento enviado (`QuoteRequest.sent_at` preenchido);
  - insistência: o lead já recebeu 1 orientação por e-mail (`email_redirect_count >= 1`).
- Fora disso, a resposta é a orientação por e-mail (`quote_recipient_email` publicado); antes de `qualificado`, a qualificação é retomada na mesma resposta.
- O 1º pedido em etapa qualificada com orçamento enviado incrementa o contador; nos demais casos recusados o contador não muda.
- Depois do link, cortesia ("ok", "obrigado") não reenvia; novo pedido explícito reenvia 1 vez, sobrescreve a marca e não repete o e-mail de aviso ao comercial.
- Negociação em `proposta_enviada` continua movendo para `negociacao` e registrando `negotiation.requested`; só marca, link e aviso seguem o gate.
- Sem número comercial publicado: comportamento anterior mantido.

## 2. `STATUS_ATUAL.md`

Atualizar o estado do agente em produção (após o deploy):

- Fatia 2B (escalação filtrada) entregue na branch `feat/scansolo-escalacao-filtrada`, corrigindo a Fatia 2 (`scansolo-escalacao-comercial-wame`).
- Migração aditiva `20261116100001_add_email_redirect_count_to_scan_solo_pipeline_opportunities` (coluna `email_redirect_count`, default 0, sem backfill). Total de migrações ScanSolo: 47.
- Novo componente `ScanSolo::Commercial::EscalationGate`, chamado só pelo `Commercial::EscalationService` (único escritor da marca e do contador).
- Nova violação regenerável do validador: `commercial_link_not_allowed`.
- Novo audit: `commercial.escalation_refused` (recusa do gate, sem telefone no payload).
- Pendência: correção manual de Daiane, Alexandre e Azanis (ver item 6).

## 3. `claude/FUNCIONAMENTO_ATUAL_*.md`

Na seção de escalação comercial / atendimento humano, substituir a descrição dos gatilhos antigos (escalação em qualquer etapa por assunto de orçamento, dúvida sem resposta na base ou pedido de humano) por:

- O modelo sinaliza todo pedido comercial ou de humano com `escalate_to_commercial` (ou `negotiation_requested`), em qualquer etapa; isso só sinaliza.
- Decisão do gate, nesta ordem:

| # | Situação | Resultado | Contador |
|---|---|---|---|
| 1 | `novo_lead`, `em_contato`, `em_qualificacao` | e-mail primeiro + retoma a qualificação (`before_qualified_ask` / `before_qualified`) | inalterado |
| 2 | etapa qualificada sem orçamento enviado | `quote_pending` | inalterado |
| 3 | etapa qualificada + orçamento enviado, contador 0 | `quote_sent` | +1 |
| 4 | etapa qualificada + orçamento enviado, contador ≥ 1 | link `wa.me` 1 vez (`escalation_reply`) + marca | inalterado |

- O e-mail de aviso ao comercial só sai na 1ª escalação real da oportunidade.
- `{{LINK_ARTUR}}` só vira link quando o turno teve escalação aprovada; em qualquer outro caso é removido. O validador bloqueia o link comercial fora disso (`commercial_link_not_allowed`).
- Lead orientado por e-mail não fica com marca: a cadência segue normal; `escalado_wa` no Kanban/relatórios só para escalação real.
- Takeover humano real: inalterado.

## 4. `CHANGELOG.md`

Entrada da versão do deploy:

- **fix(escalação)**: o link `wa.me` do comercial só é entregue a lead qualificado, com pedido de orçamento enviado, que insiste depois de 1 orientação por e-mail (DEC-060).
- **feat(escalação)**: orientação por e-mail primeiro em todo pedido comercial ou de humano; antes de `qualificado` a resposta retoma a qualificação.
- **fix(escalação)**: o link não é mais reenviado em respostas de cortesia ("Ok", "obrigado").
- **feat(validador)**: nova violação `commercial_link_not_allowed` (link comercial sem escalação aprovada, ou repetido).
- **db**: coluna `scan_solo_pipeline_opportunities.email_redirect_count` (aditiva, default 0).

## 5. `claude/AGENTE_CONFIG_V4.md`

Registrar o novo texto das regras fixas de escalação (constante `ESCALATION_RULES` em `app/services/scan_solo/ai_turn/prompt_builder.rb`, emitida só com número comercial publicado; não editável por config). Remover os gatilhos antigos 2) assunto de orçamento, 3) sem resposta na base e 4) pedido de humano. Texto atual (`%<email>s` = `quote_recipient_email` publicado):

1. Em qualquer etapa, sinalize com escalate_to_commercial, com o reason adequado, todo pedido de preço, prazo, cotação, locação ou negociação, toda dúvida sem resposta na base de conhecimento e todo pedido para falar com uma pessoa, um humano ou um atendente. Isso só sinaliza o pedido: quem decide o encaminhamento ao Artur, do comercial, é a aplicação.
2. Antes de qualificado (novo_lead, em_contato ou em_qualificacao): explique que valores e prazos vêm na proposta que o comercial envia por e-mail, informe o e-mail %<email>s e siga com a próxima pergunta pendente, sem repetir o que já foi respondido.
3. Em qualificado, proposta_enviada ou negociacao: oriente primeiro por e-mail; o cliente pode responder ao e-mail da proposta ou escrever para %<email>s.
4. O contato comercial é o Artur. Para passar o contato, escreva apenas {{LINK_ARTUR}} na resposta; nunca escreva URL, link de WhatsApp ou telefone. Só a aplicação entrega o contato, quando aprova o encaminhamento.
5. Depois de o contato do Artur ter sido entregue, não o repita em respostas de cortesia (como "ok" ou "obrigado") e continue respondendo o que a base de conhecimento cobre.
6. Você é o especialista virtual da ScanSOLO (regra do especialista virtual e transparência de IA, sem mudança).

Também registrar os textos fixos aprovados (`config/locales/en.yml`, `scan_solo.commercial.email_first.*`): `before_qualified`, `before_qualified_ask`, `quote_pending`, `quote_sent` — redação literal em `APROVACAO.md`. A entrega do link reutiliza `scan_solo.negotiation.escalation_reply`, sem mudança.

## 6. `BACKLOG.md`

Adicionar o item:

- **Correção manual pós-deploy dos leads marcados indevidamente — Daiane (conv. 122), Alexandre (conv. 120) e Azanis (conv. 86).**
  - Só depois do deploy da Fatia 2B e com autorização explícita do Leo; pontual, lead a lead, nunca em lote automático; não retroativo.
  - O quê: limpar `escalated_to_commercial_at` e `escalation_reason` das 3 oportunidades (saem de `escalado_wa` e a cadência deixa de ficar em defer `commercial_escalated`). `email_redirect_count` fica 0.
  - CSI (conv. 111) foi a escalação legítima: manter a marca. Com contador 0 (sem backfill), o próximo pedido dela recebe 1 orientação por e-mail antes de um novo link (comportamento aceito).
  - Registrar a correção (quem autorizou, data, oportunidades) em `STATUS_ATUAL.md`.
