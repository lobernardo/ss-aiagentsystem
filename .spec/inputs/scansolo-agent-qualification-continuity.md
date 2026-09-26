# ScanSolo — Continuidade do agente e resolução canônica de qualificação (Ciclo 1)

> Input para `/bc-harness:plan ".spec/inputs/scansolo-agent-qualification-continuity.md"`.
> Base: `feat/make-credentials` (= `fix/knowledge-crlf-chunking@017ecb9430` + patch 0004 de credenciais do Make), a que estiver em produção quando o ciclo começar.
> Branch: `fix/agent-qualification-continuity` criada a partir dessa base.

## Problema atual (reproduzido em produção, 2026-09-25)
1. Lead responde "Leonardo" e o agente volta a perguntar o nome (e depois "nome completo").
2. Lead pergunta sobre tubulação de PVC e o agente prioriza pedir o nome em vez de responder.
3. Dados informados juntos ("obra no Rio, 800 m², escavar amanhã") não são todos registrados.
4. Lead só diz "Boa tarde" e o agente cumprimenta de novo na 2ª resposta ("Boa tarde, Milena!" duas vezes).

Mitigação já aplicada (sem código): config v2 do Agent Center (25/09 noite). "Nome" e "Telefone" foram
**retirados** de `required_qualification_fields` só porque o resolvedor não existe; depois deste ciclo "Nome" volta.

Campos obrigatórios publicados hoje (config v2):
`Objetivo do serviço`, `Cidade / UF`, `Endereço da obra`, `Área ou extensão`, `Profundidade de interesse`,
`Prazo desejado`, `Integração de segurança`, `Empresa`, `E-mail`.

## Causa raiz (confirmada no código)
- `ai_turn/context_assembler.rb#pipeline_context` calcula `missing_fields` só por
  `contact.custom_attributes.slice(*required_qualification_fields)`. Campos nativos (`contact.name`, `email`,
  `phone_number`) nunca satisfazem um campo obrigatório; não há normalização de chave (caixa/acento/alias).
- `actions/qualification_field_action.rb` descarta em silêncio chaves que não batem **exatamente** com
  `required_qualification_fields` (ex.: modelo envia `cidade_uf`, config tem `Cidade / UF`).
- A mesma regra "campo satisfeito?" está duplicada em 6 lugares, cada um com sua lógica:
  `context_assembler.rb`, `qualification_field_action.rb`, `cadence/reply_completeness_detector.rb`,
  `proposal/generate_service.rb`, `proposal/make_provider.rb`, `handoff/handoff_service.rb`.
- `ai_turn/prompt_builder.rb` não tem regras fixas de não repetição, prioridade da pergunta atual nem saudação única.

## Comportamento esperado
- Um único resolvedor determinístico (ex.: `ScanSolo::Qualification::FieldResolver`) responde, para cada campo obrigatório:
  valor atual + origem (`native` | `custom_attribute`) + satisfeito?
  - mapa nativo: nome → `contact.name`; e-mail → `contact.email`; telefone → `contact.phone_number`;
  - demais → `contact.custom_attributes`;
  - comparação de chave normalizada (trim, case-insensitive, sem acento, `_`/espaço/`/` equivalentes) + aliases.
  - aliases mínimos: "Nome"/"nome completo"/"name" → nome; "E-mail"/"email" → e-mail; "Telefone"/"WhatsApp" → telefone;
    e as chaves que o Make já aceita: `empresa`, `endereco_obra`, `cidade_uf`, `tipo_intervencao` (≈ Objetivo do serviço),
    `area` (≈ Área ou extensão), `profundidade`, `prazo_desejado`.
- Os 6 consumidores acima passam a usar só o resolvedor (writer/reader único).
- `qualification_field` aceita chaves normalizadas/aliases, grava todas as reconhecidas de uma vez (captura múltipla),
  **não sobrescreve** campo nativo já preenchido (nome do perfil WhatsApp) e registra chave não reconhecida na evidência
  da ação (não some em silêncio).
- `PromptBuilder` adiciona três regras fixas (não editáveis pelo config), antes das regras do config:
  1. "Nunca pergunte novamente informação já presente no contato, nos campos coletados ou no histórico."
  2. "Responda primeiro à pergunta/intenção atual do cliente; só depois peça no máximo um campo faltante."
  3. "Cumprimente apenas na primeira resposta da conversa; não repita saudação depois."
  E instrui registrar todos os dados informados na mensagem via `qualification_field`.
- `make_provider` envia ao Make os campos já resolvidos (inclui nome/e-mail/telefone nativos) nas chaves que o Make aceita.

## Regras / restrições
- Resolvedor é determinístico: **não** extrai dados do histórico por regex/LLM; só lê dados estruturados.
- Não alterar contrato das APIs públicas (CT-01..CT-11) além de expor, opcionalmente, a origem do campo no detalhe da oportunidade.
- Sem migration destrutiva. Aliases em constante (preferido) ou jsonb aditivo no config; decidir no PLAN.
- Nenhuma dependência de `enterprise/`/`Captain::`.
- Incluir de carona: `# rubocop:disable Rails/SkipsModelValidations` inline em
  `spec/services/scan_solo/knowledge/ingestion_service_spec.rb` (linha do `update_columns` do teste CRLF).

## Não escopo
- Kanban/UX, templates, Make (cenários), RAG, esconder "Campos faltantes" por etapa (ciclo 2).
- Aumentar janela de histórico (20 msgs) — só se o PLAN provar necessidade.

## Riscos
- Sobrescrever `contact.name` do WhatsApp com valor pior → mitigado por "não sobrescreve nativo preenchido".
- Mudança de satisfação de campos pode antecipar transição para `qualificado` e disparar gate de proposta → cobrir em spec.
- `ReplyCompletenessDetector` passa a cancelar mais tentativas de cadência → validar recálculo.
- Oportunidades com dados gravados em chaves antigas passam a ser reconhecidas via alias (efeito desejado) → cobrir em spec.

## Produção
- Deploy com `deploy-release.sh fix/agent-qualification-continuity <commit>` (sem recarregar cadências).
- Pós-deploy: recolocar "Nome" nos campos obrigatórios do Agent Center; repetir teste real (nome + PVC + "Boa tarde" duas vezes)
  com contato controlado; conferir `GET /scan_solo/ai_turns/:correlation_id`.

## Testes (obrigatórios)
- Resolvedor: nome nativo satisfaz "Nome"; "nome completo"/"NOME"/"name" resolvem por alias; custom attribute com acento/caixa
  diferente; chaves do Make (`cidade_uf`, `endereco_obra`...) satisfazem os campos da config v2.
- Ação: `{nome: "Leonardo", cidade_uf: "Rio/RJ", area: "800 m²", prazo_desejado: "amanhã"}` grava todos os reconhecidos;
  não sobrescreve nome nativo; chave desconhecida aparece na evidência.
- Contexto/prompt: payload contém as 3 regras fixas; `missing_fields` não contém Nome/E-mail quando nativos existem.
- Os 6 consumidores retornam o mesmo resultado para o mesmo contato (spec de consistência).
- Integração (mock LLM): lead já com nome + pergunta técnica → resposta sem pergunta de nome; resposta parcial;
  dados fora de ordem; retorno após handoff.
- Regressão: `./scripts/ralph-test.sh` verde.
