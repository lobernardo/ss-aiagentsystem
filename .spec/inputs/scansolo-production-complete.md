# ScanSolo Production Complete

## Objetivo

Finalizar o ScanSolo/Chatwoot para produção real, partindo da implementação já existente no ciclo `scansolo-chatwoot-platform`.

NÃO reimplementar funcionalidades já existentes.
NÃO recriar as fases anteriores.
Auditar e reutilizar o código existente.

O objetivo deste incremento é:

- corrigir gaps identificados;
- conectar componentes já implementados;
- fechar fluxos ponta a ponta;
- remover mocks perigosos;
- corrigir deploy;
- tornar o sistema seguro para go-live;
- executar os gates necessários para ativação em produção.

## Fontes obrigatórias

Ler integralmente antes de planejar:

- `docs/scansolo-production-complete/CURRENT_STATE.md`
- `docs/scansolo-production-complete/ARCHITECTURE_MAP.md`
- `docs/scansolo-production-complete/GAP_ANALYSIS.md`
- `docs/scansolo-production-complete/RISK_REGISTER.md`
- `docs/scansolo-production-complete/DECISIONS_REQUIRED.md`

Ler também o ciclo anterior para evitar reimplementação:

- `.spec/features/scansolo-chatwoot-platform/SPEC.md`
- `.spec/features/scansolo-chatwoot-platform/PLAN.md`
- `.spec/features/scansolo-chatwoot-platform/PHASES.md`
- `.spec/features/scansolo-chatwoot-platform/openapi.yaml`
- `.spec/features/scansolo-chatwoot-platform/asyncapi.yaml`

## Prioridade

Prioridade absoluta: colocar o Chatwoot/ScanSolo em produção de forma segura no menor número possível de fases.

P0 primeiro. Melhorias P1/P2 que não bloqueiam produção devem ficar depois dos fluxos críticos.

## Escopo obrigatório

### 1. Runtime da IA

Corrigir o fluxo canônico do turno.

O contexto já recuperado deve efetivamente chegar ao modelo:

- histórico;
- knowledge/RAG;
- contexto do contato;
- contexto da oportunidade/pipeline;
- memória;
- regras do agente.

Conectar também os campos já existentes do AiAgentConfig que hoje são gravados mas não usados:

- service_hours;
- response_limits;
- transfer_criteria;
- restricted_information;
- qualification_playbook.

Garantir:

- nenhum turno preso permanentemente em `pending`;
- exceções marcadas como failed;
- retry idempotente;
- recheck de elegibilidade imediatamente antes do envio;
- uma única resposta válida por fluxo/conversa;
- proteção contra rajadas de mensagens;
- nenhuma dupla resposta humano + IA.

### 2. Pipeline

Criar automaticamente `PipelineOpportunity` quando um lead elegível entrar pela primeira vez.

Regra:

- primeira mensagem inbound;
- conta ScanSolo habilitada;
- inbox permitido;
- criar oportunidade somente se ainda não existir;
- estágio inicial `novo_lead`.

Manter uma oportunidade por conversa.

Ao entrar nos estágios configurados, ligar automaticamente a cadência correspondente.

### 3. Agent Actions

Conectar ao runtime a camada existente:

- Actions::Registry;
- Actions::Executor;
- QualificationFieldAction;
- HandoffAction;
- CadenceSignalAction;
- StageTransitionAction;
- ProposalActions;
- PrivateNoteAction.

A IA deve conseguir executar ações somente pela camada autorizada existente.

Nenhuma gravação paralela ou bypass das policies/actions.

### 4. Handoff humano

Implementar o fluxo completo.

Resposta humana ou takeover deve impedir resposta posterior da IA naquele turno.

Regras:

- humano assume → IA pausa;
- humano responde manualmente → tratar como takeover;
- takeover pausa/cancela automação aplicável;
- devolver para IA → reativar IA;
- recalcular fluxo/cadência conforme estado atual;
- montar o `HandoffControlBanner` na conversa;
- suportar os estados necessários já existentes;
- impedir IA e humano responderem simultaneamente.

### 5. Cadências

Usar as regras já definidas para ScanSolo.

Novo Lead:
- +2h
- +24h
- +48h
- +96h

Em Contato:
- 5 tentativas
- intervalo de 24h

Em Qualificação:
- 7 tentativas
- intervalo de 24h

Janela:
- 09:00–20:00
- America/Sao_Paulo
- horizonte de 7 dias

Também:

- carregar as CadenceDefinitions corretamente em produção;
- auto-enroll ao entrar no estágio;
- resposta do lead cancela/recalcula jobs pendentes;
- resposta parcial recalcula;
- takeover humano suspende;
- devolver à IA permite retomada coerente;
- opt-out impede novos envios;
- checar `scansolo_enabled`;
- checar estado de handoff;
- checar status da conversa;
- indisponibilidade temporária de template NÃO deve consumir tentativa definitivamente;
- permitir re-enroll quando a regra de negócio exigir;
- gravar evidência correta;
- não marcar como enviado antes de existir evidência confiável do envio.

### 6. Templates WhatsApp / Meta

Continuar usando exclusivamente o WhatsApp Cloud API nativo do Chatwoot.

Não criar cliente paralelo.
Não usar Evolution.

Corrigir integração de templates para suportar:

- template por etapa/tentativa;
- idioma;
- parâmetros;
- disponibilidade;
- status approved/rejected/paused;
- motivo de bloqueio;
- último sync.

Nunca enviar template indisponível.

Manter os dados externos de Meta como gate humano quando exigirem credenciais/configuração externa.

### 7. Propostas / Make

O `MockProvider` não pode permanecer utilizável em produção.

Integrar corretamente o fluxo existente de Make quando as credenciais e contrato externo estiverem disponíveis:

Chatwoot
→ MakeRequest
→ Make
→ callback autenticado
→ ProposalVersion
→ aprovação
→ envio

Corrigir:

- OutboundRequestService sem chamador;
- callback que hoje não aplica em ProposalVersion;
- correlation id;
- idempotência;
- callback rejeitado não pode inutilizar callback válido posterior;
- retry;
- dead letter;
- failure_reason;
- reprocessamento.

Enquanto a integração externa real não estiver configurada, generate/send de proposta deve permanecer bloqueado em produção.

Nunca enviar preço ou PDF mock ao cliente.

### 8. Agent Center / UX

Corrigir imediatamente:

- scroll vertical;
- responsividade;
- chaves i18n cruas;
- mapeamento camelCase → chaves corretas;
- organização do Agent Center;
- seções;
- feedback salvar/publicar;
- loading;
- erros;
- toasts;
- confirmação;
- alterações não salvas;
- require_proposal_approval;
- modelo/provider;
- timestamps legíveis;
- labels amigáveis;
- IDs técnicos escondidos para operadores quando não necessários.

Não quebrar padrões visuais do Chatwoot.

### 9. Knowledge / RAG

Além de colocar RAG no prompt:

- update de content deve reindexar;
- registrar estado de indexação;
- erro de indexação;
- indexed_at;
- evitar fonte aparentemente válida com 0 chunks silenciosamente;
- knowledge_evidence no turno.

PDF e crawler/site NÃO devem bloquear o go-live principal.

Se forem implementados neste incremento, devem ficar depois dos P0.

Qualquer crawler deve usar proteção SSRF.

### 10. Segurança

Corrigir:

- AiAgentConfigPolicy;
- KnowledgeSourcePolicy;
- publish somente para papel autorizado;
- knowledge somente para papel autorizado;
- auditoria administrativa;
- rate limiting de endpoints caros;
- guard frontend/backend da feature;
- logging sem expor segredos;
- não apagar UUID/correlation ids necessários à observabilidade;
- coexistência Captain × ScanSolo;
- inbox allowlist.

ScanSolo não deve responder em inbox não autorizado.

### 11. Captain

Evitar dupla resposta Captain + ScanSolo.

Implementar guard explícito ou garantir tecnicamente exclusividade por inbox.

Nunca permitir que ambos respondam à mesma mensagem.

### 12. Deploy de produção

Corrigir o Git para refletir a VPS e impedir drift.

Obrigatório:

- `POSTGRES_PASSWORD=${POSTGRES_PASSWORD}`;
- compose de produção não pode herdar compose de desenvolvimento;
- não expor Postgres;
- não expor Redis;
- não subir vite;
- não subir mailhog;
- não montar source bind de desenvolvimento;
- não ativar Caddy;
- manter Nginx/TLS da VPS;
- build reproduzível;
- GIT_SHA via build arg ou mecanismo confiável;
- `.env.example` com nomes necessários, nunca valores;
- carregar cadências;
- backup;
- migrations;
- restart Rails;
- restart Sidekiq;
- smoke test;
- rollback executável.

Nunca alterar domínio, Nginx ou certificados existentes durante o Ralph.

### 13. Observabilidade

Garantir visibilidade mínima de produção:

- AiTurn status;
- provider;
- model;
- tokens;
- latency;
- failure_reason;
- correlation id;
- knowledge evidence;
- cadence attempts;
- templates;
- callbacks Make;
- handoffs;
- erros recentes.

### 14. Teste controlado de produção

Criar roteiro e critérios de aceite.

Go-live mínimo exige:

1. mensagem real chega pelo WhatsApp;
2. exatamente um turno é criado;
3. exatamente uma resposta da IA;
4. RAG utilizado;
5. PipelineOpportunity criada;
6. estágio correto;
7. cadência coerente;
8. resposta humana pausa IA;
9. retorno à IA funciona;
10. nenhuma proposta mock disponível;
11. logs/correlation id disponíveis;
12. nenhuma duplicidade de envio.

## Restrições

- Não mexer em Nginx/TLS/domínio durante implementação.
- Não versionar segredo.
- Não depender do código enterprise para a camada ScanSolo.
- Não reimplementar Chatwoot upstream.
- Não criar transporte WhatsApp paralelo.
- Não enfraquecer testes existentes.
- Não remover funcionalidades já implementadas para simplificar.
- Preferir wiring/correção do que já existe.
- Mudanças destrutivas de banco exigem justificativa explícita.
- Toda mudança relevante deve ter teste.
- Manter compatibilidade com a VPS atual.

## Planejamento

Gerar:

- SPEC.md
- PLAN.md
- PHASES.md

Slug obrigatório:

`scansolo-production-complete`

Organizar em poucas fases coerentes, priorizando primeiro os bloqueadores de go-live.

Credenciais, Meta, Make, SMTP, LEXUS e outros dados externos que não estejam disponíveis devem virar HUMAN GATES claramente identificados, e não impedir a implementação do restante.

Não interromper o planejamento para perguntas que possam ser resolvidas pelos documentos existentes ou por defaults seguros já documentados.

