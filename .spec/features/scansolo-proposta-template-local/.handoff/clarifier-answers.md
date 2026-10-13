# Clarifier answers — 2026-10-13

## Premissa corrigida pelo desenvolvedor (substitui M-01, M-02 e Q-02/Q-03 do analyze)

**Qualificação do agente ≠ validação do template.** O template não valida nem reinventa a qualificação; ele só renderiza os dados já qualificados + a resposta oficial do Luciano.

Regra de qualificação (decisão do desenvolvedor, verbatim resumido):
1. O agente qualifica com base no treinamento e nas regras de coleta existentes.
2. Para cada informação relevante: se o lead informar, persistir o valor; se o lead disser explicitamente que não sabe, não tem, ainda não foi definido ou não se aplica, isso conta como **resposta válida**; não perguntar indefinidamente.
3. A solicitação de orçamento só dispara quando a qualificação estiver concluída por essa regra: **campo preenchido OU explicitamente indisponível/não informado**.
4. O template renderiza; não reinventa a qualificação.
5. Dado do lead ausente (faltante ou explicitamente não informado) → representação neutra ("Não informado") ou omissão do trecho quando fizer mais sentido visualmente.
6. Profundidade faltante nunca trava a geração.
7. Só bloqueiam a geração os campos indispensáveis da resposta comercial: valor total, prazo/cronograma, escopo/atividades, condições de pagamento (já garantidos pelo parser OC/CT-04 — só resposta válida chega à geração). Fora isso, só bloqueiam falhas técnicas: template indisponível/inválido e conversão (Gotenberg).

### Auditoria do código de qualificação (feita pelo router em 2026-10-13, para o SPEC registrar no AS IS)

- Catálogo fechado de 34 chaves em `ScanSolo::Qualification::FieldResolver::CATALOG` (`field_resolver.rb:24-59`).
- Obrigatórios: lista por conta `required_qualification_fields` da config publicada (labels → chave canônica por alias; default `[]` no banco). O valor em produção não está no repositório (só lido na VPS).
- Status de campo: só `confirmado | inferido | faltante` (`lead_state.rb:8`). `Writer#apply_field!` ignora valor em branco (`writer.rb:22-23`); o schema da ação `qualification_field` aceita só `confirmado`/`inferido` (`qualification_field_action.rb`).
- Satisfeito = `confirmado` (`field_resolver.rb` `fields`); `CompletionService` conclui quando todo obrigatório está `confirmado` e só então, com próxima ação `proposta`, enfileira o `QuoteRequestJob`.
- Elegíveis para pergunta = obrigatórios `faltante`; o `OutputValidator` regenera a resposta se perguntar campo não `faltante` (`output_validator.rb:22,76`); regra de prompt "nunca pergunte novamente informação já presente no histórico" (`prompt_builder.rb:26-34`), mas é só instrução.
- **Não existe representação de "não sabe / não tem / não se aplica"**: o modelo ou grava um texto livre como `confirmado` (não instruído, não determinístico) ou deixa `faltante` — e aí o campo continua elegível e pode ser perguntado de novo indefinidamente, e a qualificação nunca conclui. `PromptBuilder::NOT_INFORMED` é só texto de exibição.
- Profundidade só é obrigatória se estiver na lista publicada da conta (o código não a força).

### Mudança de qualificação incluída nesta feature (Parte A, separada da Parte B — template)

- Novo status de campo `nao_informado` ("explicitamente indisponível"): o lead declarou que não sabe/não tem/não definido/não se aplica. Valor = as palavras do lead (não vazio), gravado pelo `Writer` com histórico, origem na mensagem.
- Schema da ação `qualification_field`: status `confirmado | inferido | nao_informado`.
- Satisfeito = `confirmado` OU `nao_informado` em `FieldResolver` (conclusão, `missing_labels`, gate de proposta). `inferido` continua não contando.
- Elegíveis para pergunta = só `faltante`; perguntar um campo `nao_informado` é violação `field_not_missing` (regenera a resposta) — fim das perguntas infinitas.
- Precedência no `Writer`: `confirmado` substitui `nao_informado` (o lead informou depois); `nao_informado` substitui `faltante` e `inferido`; `nao_informado` nunca substitui `confirmado`; `inferido` nunca substitui `nao_informado`.
- Prompt: regra fixa "se o cliente disser que não sabe, não tem, ainda não definiu ou não se aplica, registre o campo com status nao_informado e não pergunte de novo".
- E-mail de solicitação (SO): campo `nao_informado` aparece com o texto "Não informado pelo cliente" na linha do campo e entra em "INFORMAÇÕES AINDA NÃO CONFIRMADAS" como "<rótulo> (cliente não soube informar)"; continua deterministicamente.
- Nenhuma migração: `fields` é jsonb; só a constante de status muda. Estados antigos continuam válidos.

## Respostas às perguntas do analyze

- **Q-01 (M-03): (a).** `template_render_failed` e `provider_rejected` entram em `SAFE_RETRYABLE_REASONS`; registrar no quadro de requisitos alterados que `provider_rejected` também fica reprocessável no modo Make (AP/RF-15).
- **Q-02 (M-02): substituída pela premissa.** Nenhum campo de qualificação bloqueia a geração. Representação neutra por placeholder:
  - `NOME_EMPRESA` = `empresa` → nome do contato → "Não informado".
  - `NOME_CONTATO` = `nome` (lead state → coluna nativa → custom_attribute) → "Não informado".
  - `PROJETO_CLIENTE_FINAL` = `cliente_final` → `empresa` → `nome` → "Não informado".
  - `ENDERECO_OBRA` = endereço (+ bairro) → "Não informado".
  - `CIDADE_ESTADO` = "Cidade – UF" → "Não informado".
  - `RUA_CIDADE_ESTADO` = "<endereço>, em Cidade – UF" → só "Cidade – UF" → só "<endereço>" → "localidade não informada".
  - Campo `nao_informado` é tratado como ausente (nunca imprime as palavras do lead no PDF).
- **Q-03 (M-01): omissão do trecho.** O template v3 troca a frase "com foco até {{PROFUNDIDADE}} de profundidade" por `{{TRECHO_PROFUNDIDADE}}` (placeholder do trecho inteiro, já aplicado no v3 fora do repo): valor = ", com foco até <profundidade> de profundidade" com o valor exatamente como gravado (`profundidade` → `profundidade_intervencao`), ou vazio quando ausente/`nao_informado`. `{{PROFUNDIDADE}}` deixa de existir; continuam 16 placeholders.
- **Q-04: (a).** Auditoria `proposal.generation_failed` ganha `cause` (`template` | `conversion` | `exception`) e, quando houver, `placeholders` (só nomes, nunca valores); campo opcional extra no payload do `CallbackHandler`. (`missing_data` não existe mais: dado ausente não falha.)
- **Q-05: (a).** Blob enviado antes, fora de transação (`ActiveStorage::Blob.create_and_upload!`); sob o lock só revalida, anexa o blob e aplica o resultado; revalidação falhou → purge do blob órfão; falha no upload → caminho de falha (RF-12).
- **Q-06: (b) provisório.** `DATA_SOLICITACAO` = data de criação da `quote_request` (dia em que a solicitação foi enviada ao comercial), por extenso, America/Sao_Paulo. Marcar como decisão a confirmar pelo desenvolvedor no checkpoint (não bloqueia o plano; troca é 1 linha).
- **Q-07: (a).** O v3 tem exatamente os 16 placeholders (13 do v2 com `PROFUNDIDADE`→`TRECHO_PROFUNDIDADE` + `PRAZO_CRONOGRAMA`, `CONDICOES_PAGAMENTO`, `OBSERVACOES_COMERCIAIS`); nada de `AREA_TOTAL`, `ENDERECO_LOGRADOURO`, `LOCAL_SERVICO`. Aprovação visual do v3 = gate humano HG-T1 antes do upload em produção.
- **Q-08: (a).** Aceito + AC: resposta sem template → `failed`/`template_unavailable`; upload → estado `configured`, Reprocessar habilitado → sucesso.

# Round 2 — 2026-10-13 (router, aplicando a premissa do desenvolvedor: as palavras "não sei" do lead nunca viram valor)

- **D-02: confirmado.** "Nada bloqueia" vale para a Parte B; o gate existente do `GenerateService` continua, com a nova regra de satisfeito (`confirmado` OU `nao_informado`).
- **D-03:** no e-mail SO, linha opcional de campo `nao_informado` mostra "<rótulo>: Não informado pelo cliente"; o campo entra nas pendências como "<rótulo> (cliente não soube informar)"; itens fixos do SO/CT-07 satisfeitos por esse campo continuam listados com o mesmo sufixo.
- **D-04: confirmado.**
- **Q-new-1:** valor `nao_informado` NÃO é espelhado no contato (nem coluna nativa nem `custom_attributes`); o contato guarda só dado real.
- **Q-new-2:** todo leitor trata `nao_informado` como ausente para fins de valor: `EmailComposer#lead_name` cai no próximo fallback; `NegotiationPayload.contact` e `FieldResolver#make_qualification` omitem; `_pipeline_opportunity.json.jbuilder` expõe `status: "nao_informado"` com `value` (para auditoria na tela) e a UI mostra o rótulo neutro; `collected`/contexto do turno e nota de handoff mostram "<rótulo>: não informado pelo cliente" (o agente precisa saber que já foi respondido, sem repetir as palavras como dado).
- **Q-new-3:** sim, requisito de UI: `scansoloLabels.js` + `en.json` ganham o status `nao_informado` = "Não informado pelo cliente" (só `en.json`, regra do projeto).
