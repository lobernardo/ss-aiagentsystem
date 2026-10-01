# Phases: scansolo-operacao-centralizada

Gerado por /plan a partir de PLAN.md — view executável para `./ralph.sh .spec/features/scansolo-operacao-centralizada/PHASES.md`.

Regras transversais (de `AGENTS.md`/`CLAUDE.md`, `docs/agents/architecture.md`, `docs/agents/domain_rules.md`):
- Controllers: gate 404 `scansolo_enabled`, Pundit (403) e validação de borda (422). Services: regras, transações, locks e auditoria. Listener: só classifica e delega. Models: enums, associações e validações.
- `ScanSolo::Pipeline::StageTransitionService` é o único escritor de etapa. `FieldResolver` é o único leitor de "satisfeito". `CallbackHandler` é o único escritor de `value`/`currency`/`artifact_url`.
- RNF-01: chamada ao Make, download do PDF, mensagens WhatsApp novas e mensagens de e-mail só depois do commit (`ActiveRecord.after_all_transactions_commit` ou job).
- Reusar o nativo: `ContactInboxBuilder`, `ContactInboxWithContactBuilder`, `ConversationBuilder`, `ConversationReplyMailer` (via `Message`), `SafeFetch`, ActiveStorage e `NativeTemplateSender`. Sem SMTP, IMAP ou HTTP próprio com a Meta.
- Migrações só aditivas. Sem colunas em tabelas do Chatwoot. 0 referências a `enterprise/`/`Captain::`.
- i18n: backend em `config/locales/en.yml` (seção `scan_solo`); frontend em `app/javascript/dashboard/i18n/locale/en/scansolo.json`. Sem strings soltas.
- Estilo: classe compacta `class ScanSolo::...`, 1 classe por arquivo, ≤150 colunas, header comment com RF/CT/RNF. Vue com `<script setup>`, Tailwind e `components-next/`.
- Specs Ruby e rubocop: `docker exec scansolo-phase2-test sh -c 'cd /app && bundle exec rspec <paths>'` (idem `bundle exec rubocop <paths>`). Depois da Phase 1: `docker exec scansolo-phase2-test sh -c 'cd /app && RAILS_ENV=test bundle exec rails db:migrate'`. Vitest: `pnpm test <paths>`. ESLint com os `.vue` explícitos.
- RNF-11: um spec existente só muda de expectativa quando reflete mudança intencional do SPEC, citando o requisito na task. Nunca flexibilizar, remover ou pular (`skip`/`pending`/`xit`) um teste para fazê-lo passar.
- As Phases 7, 16, 17, 18 e 19 NÃO são executadas pelo `ralph.sh`: são de operador/humano (configuração Chatwoot/Meta, Make via MCP com aprovação do desenvolvedor, verificação com evidência). Os checkboxes ficam para registro e só são marcados `[x]` com a evidência descrita.

## Phase 20: Remoção condicional do aprovar/enviar legado (RF-55 Etapa 2)

Antes de implementar, leia:
1. `.spec/features/scansolo-operacao-centralizada/SPEC.md` — requisitos RIGID que esta fase cobre
2. `.spec/features/scansolo-operacao-centralizada/PLAN.md` — decomposição completa, dependências e riscos
3. `.spec/features/scansolo-operacao-centralizada/openapi.yaml` — `x-deactivated-paths` (CT-11)
4. `.spec/features/scansolo-operacao-centralizada/make/REGISTRO-LEGADO.md` — conclusão da Phase 19 (sem "sem uso", esta fase termina sem mudança de código)

- [ ] T32 — Remoção condicional do aprovar/enviar legado (RF-55 Etapa 2, CT-11)
      Arquivos: só se `.spec/features/scansolo-operacao-centralizada/make/REGISTRO-LEGADO.md` (T41) concluir "sem uso": `config/routes.rb`, `app/controllers/api/v1/accounts/scan_solo/proposals_controller.rb`, `app/policies/scan_solo/proposal_policy.rb`, `app/services/scan_solo/proposal/approve_service.rb` (removido), `app/services/scan_solo/proposal/send_service.rb` (removido), `app/views/api/v1/accounts/scan_solo/proposals/approve.json.jbuilder` (removido), `app/views/api/v1/accounts/scan_solo/proposals/send_proposal.json.jbuilder` (removido), `app/services/scan_solo/proposal/make_provider.rb`, `app/services/scan_solo/proposal/mock_provider.rb`, `app/services/scan_solo/proposal/callback_handler.rb`, `app/javascript/dashboard/store/scansolo/proposals.js`, `app/javascript/dashboard/api/scansoloProposals.js`, `docs/agents/api_contracts.md`, `docs/agents/domain_rules.md`, `spec/services/scan_solo/proposal/approve_service_spec.rb` (removido), `spec/services/scan_solo/proposal/send_service_spec.rb` (removido), `spec/requests/api/v1/accounts/scan_solo/proposals_spec.rb`, `spec/services/scan_solo/proposal/make_provider_spec.rb`, `spec/services/scan_solo/proposal/mock_provider_spec.rb`, `spec/services/scan_solo/proposal/callback_handler_spec.rb`, `spec/integration/scan_solo/full_test_mode_spec.rb`
      Mudança:
        • Ler o `REGISTRO-LEGADO.md`. Conclusão "dependência encontrada" ou registro incompleto → não mudar nenhum arquivo, anotar no registro que o legado fica desativado e concluir a task.
        • Com "sem uso": remover rotas/actions `approve`/`send_proposal`, policies `approve?`/`send?`, `ApproveService`, `SendService`, `request_send` (Make e Mock), as 2 views e os métodos `approve`/`send` do store/API; `apply_send_result!` continua para callbacks históricos e chama `DeliveryService` no sucesso; docs passam CT-11 a "removido"; reexecutar os gates do T35.
        • Sempre preservados: coluna `require_proposal_approval`, enum `approved`, `approved_at`, `MakeCallback` históricos.
      Cobre: RF-55, CT-11, RNF-10, RNF-11
      Acceptance criteria: com "sem uso": `POST .../proposals/:id/approve` e `.../send` → 404, versão `approved` histórica → `GET` inalterado, callback `proposal.send` histórico aplicado sem erro, rubocop/eslint/`./scripts/ralph-test.sh` verdes; sem "sem uso": diff desta task vazio, rotas respondendo como antes e o registro apontando a dependência.
      Testes: `proposals_spec.rb` e specs listados (só no caso "sem uso").
