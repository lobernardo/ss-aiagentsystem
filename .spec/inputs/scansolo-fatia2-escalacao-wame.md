# Fatia 2 — Escalação ao Artur por wa.me (substitui o handoff interno do modelo)

> Input para `/bc-harness:plan`. Feature: `scansolo-escalacao-comercial-wame`. Base: commit `85f0c93fe1` (= produção em 09/11/2026).
> Decisões do Leo: DECISOES.md (DEC-048..054) e STATUS_ATUAL.md §9 no projeto.
> Nome público do contato comercial: **Artur**. "Luciano" só em código/documentos internos, nunca em mensagem externa, prompt ou KB.
> Nenhum número de telefone no Git: o WhatsApp comercial é config do Agent Center (banco).
> A Fatia 1 já está no ar e o `CommercialStatus` prevê `escalado_wa` (tratado como inexistente até esta fatia); esta fatia passa a alimentá-lo.

## Objetivo
Em último caso, o agente direciona o lead ao WhatsApp do Artur com um link `wa.me`, em vez de passar a conversa para “humano”. O agente continua a postos depois disso.

## Problema atual
- `human_handoff` (`Actions::HandoffAction` → `Handoff::HandoffService`): nota privada + `awaiting_human`; a IA para. O prompt só o permite em pedido explícito de pessoa.
- `Negotiation::RequestService`: `proposta_enviada → negociacao` + handoff + e-mail ao comercial + atribuição ao `commercial_user_id`.
- Não existe campo de WhatsApp comercial nem `wa.me` no código.

## Comportamento esperado
1. **Config nova (aditiva)** `commercial_whatsapp_number` (E.164) em `scan_solo_ai_agent_configs`, editável no Agent Center, validada. Publicada na versão v4 da config. Valor real fica só no banco.
2. **Ação `escalate_to_commercial`** (`automatic`), registrada em `Actions::Registry` e `InputGuardrail::ALL_ACTIONS`, parâmetros `conversation_id` e `reason` ∈ `duvida_sem_resposta | sem_informacao_base | negociacao | duvida_proposta | assunto_orcamento | pedido_humano`.
3. **Link montado pela aplicação** (`https://wa.me/<numero>?text=<texto URL-encoded>` com nome/empresa/serviço/ref. da proposta). O modelo usa um placeholder; `OutputValidator` rejeita qualquer `wa.me` ou telefone que não seja o publicado. O texto pré-preenchido e todas as falas dizem **Artur**.
4. **Uma resposta externa por turno**: o link vai na própria resposta do turno.
5. **Marca estruturada** `escalated_to_commercial_at` + `escalation_reason` (coluna aditiva ou tabela de eventos; decidir no PLAN) e evento de auditoria `commercial.escalated`. É a fonte para `CommercialStatus = escalado_wa` (Fatia 1).
6. **Depois do link, a IA continua ativa** (não vai para `awaiting_human`): tira dúvidas cabíveis; se o assunto for negociação, orienta sempre o `wa.me` do Artur **e** `comercial@scansolo.com.br`. Cadências ficam pausadas enquanto o lead está escalado (mesma política do handoff).
7. **Gatilhos**, em ordem: (i) lead em `qualificado`/`proposta_enviada`/`negociacao` com dúvida, objeção ou negociação; (ii) qualquer assunto de orçamento/proposta que a base não resolve; (iii) pergunta sem resposta na base (nunca inventar); (iv) pedido explícito de pessoa/humano.
8. **`Negotiation::RequestService`**: mantém a transição para `negociacao` e o e-mail de aviso ao comercial; troca “handoff + atribuição” por escalação `wa.me`. Estender para dúvida em `qualificado`.
9. **Prompt**: novas regras fixas no `PromptBuilder` (quando escalar; nunca negociar valor, prazo ou condição). Decisão explícita registrada em `DECISOES.md` (o ROADMAP veta mexer no agente sem isso).
10. O **takeover humano real** (atendente responde na tela do Chatwoot → `ConversationListener`) continua igual.

## Não escopo
Aprovação de proposta por e-mail (Fatia 4); perdido automático (Fatia 3); relatórios (Fatia 1, já no ar).

## Critérios de aceite
Link só com o número publicado e nunca inventado; “Luciano” não aparece em nenhuma mensagem externa, prompt publicado ou KB (teste); 1 resposta externa por turno; cadência pausada; as quatro situações de gatilho escalam; após escalar o agente responde nova dúvida cabível; negociação sempre cita `wa.me` + e-mail comercial; regressão do takeover humano.

## Testes
Spec de ação (registro, schema, idempotência); `OutputValidator`; `PromptBuilder` (regras fixas); integração com LLM mockado; `Negotiation::RequestService`; UI do Agent Center (campo, validação). Specs que contam migrations ou jobs do cron (`scansolo_migrations_spec`, `proposta_aprovacao_email_spec`) devem ser atualizados junto se a fatia adicionar migration ou job.

## Regras fixas (todas as fatias)
Resposta externa única por evento; LLM não controla relógio; re-checar estado antes de envio automático; nada de proposta mock ao cliente nem dado comercial inventado; migrações só aditivas; sem commit/push/merge/deploy sem autorização; specs com `scan_solo` no caminho; `./scripts/ralph-test.sh` verde; i18n só em `config/locales/en.yml` e `i18n/locale/en/scansolo.json` (pt-BR); Vue `<script setup>` + Tailwind + `components-next/`.
