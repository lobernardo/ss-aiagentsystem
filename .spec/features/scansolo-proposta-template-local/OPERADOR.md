# Operador — scansolo-proposta-template-local

Passos manuais, fora do `scripts/ralph.sh` (o ralph executa só o `PHASES.md`, fases 1–12). Nada aqui roda sem autorização explícita do desenvolvedor. Nenhum passo envia proposta real, e-mail ou WhatsApp a lead real, nem toca o Make.

## 1. D-01 — confirmar a data de `{{DATA_SOLICITACAO}}`

- Aplicado no código (T20): `created_at` da `quote_request` da versão, por extenso, `America/Sao_Paulo`.
- Alternativa: `created_at` da oportunidade. A troca é 1 linha em `app/services/scan_solo/proposal/template_values.rb` (comentário "D-01") + o exemplo de `spec/services/scan_solo/proposal/template_values_spec.rb`.
- Aceite: decisão registrada no `SPEC.md` (seção "Decisões a confirmar no checkpoint") com data.

## 2. Prova local RNF-10 (Gotenberg real, template sintético, sem envio real)

Pré-requisito: fases 1–12 concluídas.

1. Subir o Gotenberg só na stack local, sem publicar porta fora do host, por exemplo: `docker run -d --rm --name gotenberg-local --network <rede-do-compose-local> gotenberg/gotenberg:8.37.0`.
2. No `.env` local (nunca no Git): `SCANSOLO_GOTENBERG_URL=http://gotenberg-local:3000`; reiniciar `rails` e `sidekiq` locais.
3. Gerar um template sintético com os 16 placeholders (texto fictício, sem CNPJ, banco ou template real) usando o helper de spec: `bundle exec rails runner "require Rails.root.join('spec/support/scan_solo_docx_fixture'); include ScanSoloDocxFixture; File.binwrite('/tmp/template-sintetico.docx', scan_solo_docx_valid)"` (ajustar ao nome final do helper de T15). Enviar pela tela de Propostas (conta local de teste).
4. Processar 1 resposta comercial válida de teste (lead fictício, valor `12500.00`).
5. Conferir: versão `awaiting_approval`, 1 `document`; `pdf-reader` extrai o número da proposta e `12.500,00`; o e-mail de aprovação aparece só no Mailhog/ActionMailer local; nenhum e-mail ou mensagem a lead real.
6. Conferir `docker compose -f docker-compose.production.yaml -f docker-compose.scansolo.yaml config`: serviço `gotenberg` sem `ports`, com healthcheck; e `docker exec gotenberg-local curl --fail --silent http://localhost:3000/health` (valida o `curl` do healthcheck).
7. Depois: parar o container, **remover `SCANSOLO_GOTENBERG_URL` do `.env` local** (senão as specs do Make passam a rodar no modo local) e apagar `/tmp/template-sintetico.docx`.

## 3. HG-T1 — template v3 (fora do repositório)

- O desenvolvedor prepara o template v3 com os 16 placeholders do CT-03, cada um inteiro dentro de um único trecho de texto do Word (`{{TRECHO_PROFUNDIDADE}}` no lugar da frase de profundidade; sem `{{PROFUNDIDADE}}`).
- Gera um PDF de teste na stack local (passo 2 com o v3) e aprova visualmente.
- O arquivo nunca entra no Git, em fixture, em log ou em issue.

## 4. Leitura de `required_qualification_fields` em produção (somente leitura)

- Ler, na VPS, a lista publicada `required_qualification_fields` de cada conta ScanSolo, para saber quais campos passam a poder concluir a qualificação com `nao_informado` (RF-28/RF-30). Não alterar a lista (fora de escopo).
- Registrar o resultado (rótulos) no `REGISTRO.md` operacional, sem dados de leads.

## 5. HG-T2 — deploy (só pelo desenvolvedor)

1. Backup e passos do `docs/architecture/SCANSOLO_DEPLOYMENT.md` (diff de compose/`.env`, imagem nova, `rails db:migrate` com as 2 migrações aditivas).
2. `.env` da VPS: `SCANSOLO_GOTENBERG_URL=http://gotenberg:3000`.
3. `docker compose -f docker-compose.production.yaml -f docker-compose.scansolo.yaml up -d gotenberg` e conferir o healthcheck `healthy`.
4. Reiniciar `rails` e `sidekiq` (leem o `.env`).
5. Rollback rápido do modo local: remover a variável do `.env` e reiniciar `rails`/`sidekiq` (a seleção volta ao comportamento anterior).

## 6. HG-T3 — ativação em produção

1. Administrador envia o template v3 pela tela de Propostas (cartão de template); conferir nome, data e hash exibidos.
2. `bundle exec rails "scansolo:smoke[<account_id>]"` com `PASS proposal_integration`.
3. Só então processar uma resposta comercial real; conferir a 1ª versão `awaiting_approval` com PDF e o e-mail de aprovação ao comercial antes de aprovar.
4. Registrar no `REGISTRO.md` (data, hash do template, resultado do smoke).
