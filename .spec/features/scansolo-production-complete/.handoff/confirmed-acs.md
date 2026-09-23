# Confirmed input — scansolo-production-complete (tier: complete)

Summary: Colocar ScanSolo/Chatwoot em produção segura conectando/corrigindo/endurecendo o que o ciclo `scansolo-chatwoot-platform` já implementou — P0 primeiro, HUMAN GATES para dependências externas.

Source description (read fully): `.spec/inputs/scansolo-production-complete.md`

## Confirmed ACs (source of truth)
1. Turno IA recebe histórico, RAG, contato, oportunidade, memória, regras; service_hours/response_limits/transfer_criteria/restricted_information/qualification_playbook efetivos; nenhum turno preso em pending; exceções → failed; retry idempotente; recheck de elegibilidade pré-envio; uma resposta por fluxo; proteção a rajadas.
2. PipelineOpportunity auto-criada (novo_lead) no 1º inbound elegível (scansolo_enabled + inbox permitido), uma por conversa; entrada em estágio configurado → auto-enroll de cadência.
3. IA executa ações só via Actions::Registry/Executor (QualificationField, Handoff, CadenceSignal, StageTransition, Proposal, PrivateNote) — sem bypass.
4. Handoff completo: takeover/resposta humana pausa IA e automação; devolver reativa e recalcula; HandoffControlBanner montado; sem resposta simultânea humano+IA.
5. Cadências ScanSolo (Novo Lead +2h/+24h/+48h/+96h; Em Contato 5×24h; Em Qualificação 7×24h; janela 09–20 America/Sao_Paulo; horizonte 7d) carregadas em prod; cancel/recalc por resposta; takeover suspende; opt-out; checks scansolo_enabled/handoff/status; template indisponível não consome tentativa; re-enroll; evidência antes de marcar enviado.
6. Templates WhatsApp só via Cloud API nativo do Chatwoot: etapa/tentativa, idioma, parâmetros, disponibilidade, status approved/rejected/paused, motivo de bloqueio, último sync; nunca enviar indisponível.
7. MockProvider inutilizável em produção; fluxo Make (MakeRequest→Make→callback autenticado→ProposalVersion→aprovação→envio) com correlation id, idempotência, callback rejeitado não bloqueia válido posterior, retry, dead letter, failure_reason, reprocessamento; generate/send bloqueado sem credenciais reais.
8. Agent Center UX: scroll, responsividade, i18n cru, camelCase→chaves, seções, feedback salvar/publicar, loading/erros/toasts/confirmação, alterações não salvas, require_proposal_approval, modelo/provider, timestamps, labels, IDs escondidos.
9. Knowledge: update reindexa; estado/erro de indexação; indexed_at; sem fonte com 0 chunks silenciosa; knowledge_evidence no turno; PDF/crawler após P0 com SSRF.
10. Segurança: AiAgentConfigPolicy, KnowledgeSourcePolicy, publish/knowledge por papel, auditoria admin, rate limit endpoints caros, feature guard FE/BE, logs sem segredos, preservar correlation ids, inbox allowlist; exclusividade Captain×ScanSolo (nunca ambos respondem).
11. Deploy: compose prod isolado (POSTGRES_PASSWORD=${POSTGRES_PASSWORD}; sem herdar dev; sem expor Postgres/Redis; sem vite/mailhog/bind source/Caddy); Nginx/TLS VPS intocados; build reproduzível; GIT_SHA; .env.example sem valores; carga de cadências; backup, migrations, restart Rails/Sidekiq, smoke, rollback.
12. Observabilidade mínima (AiTurn status/provider/model/tokens/latency/failure_reason/correlation id/knowledge evidence, cadence attempts, templates, callbacks Make, handoffs, erros recentes) + roteiro de teste controlado com os 12 critérios de go-live do input.

## Constraints
Ver seção "Restrições" do input. Meta/Make/SMTP/LEXUS/credenciais ausentes → HUMAN GATES explícitos que não bloqueiam o resto. Poucas fases, bloqueadores de go-live primeiro. Não perguntar o que os docs já resolvem.
