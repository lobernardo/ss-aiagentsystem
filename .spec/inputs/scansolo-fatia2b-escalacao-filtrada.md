# Fatia 2B — Escalação filtrada ao Artur (e-mail primeiro, wa.me só se insistir)

> Input para `/bc-harness:plan`. Feature: `scansolo-escalacao-filtrada`. Base: `feat/scansolo-escalacao-wame` @ `7fbf336e55` (= produção); toda branch nova parte dela (DEC-045). Corrige a Fatia 2 (`scansolo-fatia2-escalacao-wame.md`).
> Nome público do contato comercial: **Artur**. "Luciano" só interno. Nenhum telefone no Git (número vive só na config do Agent Center).

## Objetivo (decisão do Leo, 16/11/2026)
Poupar o comercial (Luciano, que atende como Artur) de contatos desnecessários. O agente filtra ao máximo antes de entregar o WhatsApp. O link `wa.me` só vai para lead **já qualificado e com o pedido de orçamento enviado**, e mesmo assim **só depois de orientar por e-mail e o lead insistir**.

## Evidência (Kanban + conversas, 16/11)
4 escalações desde 10/11, só 1 dentro da regra:
- Daiane Siqueira (conv. 122), Em Contato: link na 2ª mensagem, após perguntar valor de locação. Sem qualificação, sem e-mail de orçamento.
- Alexandre Almeida (conv. 120), Em Qualificação: link ao perguntar "qual o custo aproximado?" no meio da coleta (faltavam profundidade e prazo).
- Azanis (conv. 86), Em Qualificação: link ao perguntar previsão da cotação; e-mails já coletados, mas lead não avançou a Qualificado. Pedido de orçamento não confirmado.
- CSI (conv. 111), Qualificado, orçamento encaminhado: link ao perguntar prazo; **reenviado em resposta a "Ok"**.
Causa provável: gatilhos (ii) "qualquer assunto de orçamento" e (iii) "sem resposta na base" da Fatia 2 escalam em qualquer etapa; só o (i) é limitado a qualificado+. Confirmar no código (`escalate_to_commercial`, `PromptBuilder`, `Negotiation::RequestService`).

## Regra de negócio (validada pelo Leo em 16/11)

### Elegibilidade para o wa.me (todas, checadas pela APLICAÇÃO, nunca pelo LLM)
1. Etapa >= `qualificado` (`qualificado`, `proposta_enviada`, `negociacao`);
2. pedido de orçamento ao Artur **enviado** (e-mail de solicitação registrado; confirmar o campo estruturado no PLAN. Se não existir, criar marca aditiva);
3. o lead já foi orientado por e-mail **ao menos uma vez** (`email_redirect_count >= 1`) e **voltou a pedir contato/valor/prazo** (insistência);
4. ainda não houve link nesta conversa (`escalated_to_commercial_at` nulo) ou o lead pediu de novo explicitamente depois dele.

### Escada de resposta (por etapa)
- **Antes de qualificado** (Novo Lead, Em Contato, Em Qualificação), qualquer pedido de preço, prazo, cotação, locação, negociação ou "falar com alguém": **nunca wa.me**. O agente explica que valores e prazos vêm na proposta enviada por e-mail pelo comercial, informa `comercial@scansolo.com.br` se o lead quiser escrever, e **volta à próxima pergunta pendente da qualificação** sem repetir o que já foi respondido.
- **Qualificado com orçamento enviado, 1º pedido**: orienta o e-mail (responder ao e-mail da proposta ou escrever para `comercial@scansolo.com.br`). Incrementa `email_redirect_count`. Sem link.
- **Qualificado com orçamento enviado, insistência**: aí sim entrega o `wa.me` do Artur, **uma única vez**, e marca a escalação (`escalated_to_commercial_at`, `escalation_reason`).
- **Depois do link**: IA continua ativa para dúvidas cabíveis; **não repete o link** em respostas curtas ("ok", "obrigado"). Só reenvia se o lead pedir o contato de novo de forma explícita.
- **Pedido explícito de falar com humano antes de qualificado**: mesma regra do primeiro item (e-mail, sem link). Confirmado pelo Leo.
- O **takeover humano real** (atendente responde na tela do Chatwoot) continua igual e pausa a IA/cadências.

### Definição de "insistir" (determinística, confirmada pelo Leo)
Lead volta a pedir contato/valor/prazo **depois de já ter sido orientado por e-mail uma vez**. O LLM só classifica a intenção do turno (ex.: `pede_contato_comercial`, `pede_valor_prazo`). Quem decide é a aplicação: intenção de contato + `email_redirect_count >= 1` + elegível.

## Mudanças técnicas esperadas
1. **Gate no código** em `Actions::EscalateToCommercial` (ou onde o registro/validação viver): recusar a ação (retorno estruturado, sem erro ao lead) se a elegibilidade falhar. Ação recusada vira resposta de e-mail-primeiro.
2. **`OutputValidator`**: rejeitar qualquer `wa.me`/telefone na resposta quando a conversa não for elegível ou quando já houve link e a intenção do turno não é pedir contato (antirrepetição). Defesa em profundidade além do prompt.
3. **Contador/estado**: `email_redirect_count` (aditivo, por conversa/oportunidade) e leitura do estado "orçamento enviado". Migração aditiva apenas.
4. **`PromptBuilder`**: reescrever as regras fixas de escalação conforme a escada acima. Texto externo sempre **Artur**; e-mail oficial `comercial@scansolo.com.br`. Registrar em `DECISOES.md` (nova DEC; o ROADMAP veta mexer no agente sem isso).
5. **`Negotiation::RequestService`** (estender para dúvida em `qualificado`): alinhar à mesma escada (e-mail primeiro). O e-mail de aviso ao comercial só quando a escalação wa.me de fato ocorrer, para não gerar ruído.
6. **Relatórios (Fatia 1)**: `CommercialStatus = escalado_wa` só aparece nos casos legítimos. Conferir os 4 existentes.
7. **Cadências**: política atual de pausa para escalados fica; verificar que lead não escalado e não qualificado mantém cadência normal.

## Leads já marcados indevidamente
Daiane (Em Contato) e Alexandre (Em Qualificação) estão "Encaminhado ao Artur (WhatsApp)" sem elegibilidade; Azanis a confirmar. **Reverter só após o deploy e com autorização do Leo**; ação pontual, nunca em lote automático. Não retroativo por padrão.

## Critérios de aceite
- Lead não qualificado pedindo preço/prazo/locação/humano **nunca** recebe `wa.me`; recebe orientação de e-mail e a qualificação continua sem repetir perguntas respondidas.
- Qualificado com orçamento enviado: 1º pedido -> e-mail; insistência -> `wa.me` uma vez.
- Sem reenvio de link para "ok"/"obrigado".
- `OutputValidator` bloqueia `wa.me` fora das condições mesmo que o modelo tente.
- 1 resposta externa por turno; "Luciano" nunca em mensagem externa, prompt ou KB; número só o publicado.
- E-mail de aviso ao comercial só em escalação real.
- Regressão: takeover humano, cadências, Negotiation, relatórios.

## Testes
Spec do gate (matriz etapa x orçamento enviado x contador x insistência); `OutputValidator` (wa.me bloqueado/permitido; antirrepetição); `PromptBuilder` (regras fixas); integração com LLM mockado cobrindo os 4 casos reais acima (Daiane, Alexandre, Azanis, CSI); `Negotiation::RequestService`; relatórios. `./scripts/ralph-test.sh` verde (suíte completa, DEC-059).

## Pontos a confirmar no PLAN (não assumir)
- Existe campo estruturado "pedido de orçamento enviado" (e-mail de solicitação) por oportunidade? Se não, criar marca aditiva.
- Como a intenção do turno é extraída hoje (ação/guardrail) para reaproveitar na regra de insistência.
- Texto exato da orientação por e-mail (propor no PLAN; Leo aprova).

## Regras fixas (todas as fatias)
Resposta externa única por evento; LLM não controla relógio nem elegibilidade; re-checar estado antes de envio automático; nada de proposta mock nem dado comercial inventado; migrações só aditivas; sem commit/push/merge/deploy sem autorização; i18n só em `config/locales/en.yml` e `i18n/locale/en/scansolo.json` (pt-BR); Vue `<script setup>` + Tailwind + `components-next/`.

## Documentos a atualizar quando entregue
`DECISOES.md` (nova DEC), `STATUS_ATUAL.md`, `claude/FUNCIONAMENTO_ATUAL_*.md`, `CHANGELOG.md`, `claude/AGENTE_CONFIG_V4.md` (texto do prompt publicado), `BACKLOG.md`.
