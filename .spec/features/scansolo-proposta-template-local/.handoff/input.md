# Input — scansolo-proposta-template-local

Origem: pedido do desenvolvedor em 2026-10-13 ("fechar o fluxo completo: resposta do Luciano → PDF → aprovação → envio"), depois do deploy e da validação em produção de `scansolo-solicitacao-orcamento-email`. Repositório público: nada de template, dado bancário, CNPJ real ou segredo no Git.

## Objetivo

Substituir **somente** a responsabilidade hoje executada pelo Make na geração da proposta (dados → documento → PDF → artefato) por um provider local:

```
resposta comercial válida (CT-04) → GenerateService (existente) → LocalProvider (novo)
  → job: render determinístico do template .docx → Gotenberg (LibreOffice) → PDF
  → PDF anexado em ProposalVersion#document → CallbackHandler.apply_generate_result! (existente)
  → ApprovalRequestService (existente) → aprovação humana (existente) → DeliveryService (existente) → aviso/estágio/follow-up (existentes)
```

O Make está sendo abandonado para geração (o Google Workspace será cancelado; o cenário `ScanSOLO_Proposta_Entrada` está desligado). O novo caminho nunca chama o Make.

## AS IS (auditado em 2026-10-13, HEAD 3953f9f176)

- Contrato do provider: método de classe `request_generation(proposal_version:, correlation_id:, actor: nil, retry_count: 0, **)`; retorno ignorado. Chamado por `ScanSolo::Proposal::GenerateService` (`generate_service.rb:41`, após o commit) e por `ScanSolo::Proposal::RetryPolicy#retry_generate!` (`retry_policy.rb:111-117`, com novo correlation id). `request_send` não é mais usado (o envio é `DeliveryService`).
- Seleção: `ScanSolo::Proposal::Integration.provider!` (`integration.rb:12-17`) → `MakeProvider` se as credenciais `scan_solo.make.*` existem; `MockProvider` em test/dev; senão `ProposalIntegrationNotConfigured`. `configured?`/`state` alimentam o smoke `proposal_integration` (`status_report.rb:52-71`, `lib/tasks/scansolo.rake:40-48`), o endpoint de status e o banner/botões de `Proposals.vue` (`integrationBlocked`).
- `MakeProvider`: monta payload e chama `ScanSolo::Make::OutboundRequestService`; falha de transporte → versão `failed` com `failure_reason` (`timeout`/`network_error`/`provider_unavailable`/`provider_rejected`) + auditoria `proposal.generation_failed`; nunca levanta exceção. Resultado chega pelo webhook `webhooks/scan_solo/make`.
- `MockProvider`: chama `CallbackHandler.apply_generate_result!` de forma síncrona.
- `CallbackHandler.apply_generate_result!(proposal_version:, correlation_id:, success:, value:, currency:, artifact_url:, valid_until:, failure_reason:, artifact_sha256:, template_version:)`: sob lock, exige correlation id igual ao `generate_correlation_id` e `generate_callback_applied_at` vazio; sucesso → `awaiting_approval` + auditoria `proposal.generated` + `ProposalApprovalRequestJob` após o commit; falha → `failed` + auditoria `proposal.generation_failed`.
- `ApprovalRequestService#store_document` (`approval_request_service.rb:51-61`): se `document.attached?` (e não é redownload), **não baixa nada**; senão `SafeFetch` do `artifact_url`. Depois envia ao `quote_recipient_email` o e-mail de aprovação com o PDF.
- `ProposalVersion`: `has_one_attached :document`; `proposal_number` (`SS-AAAA-NNNNNN`) gerado no `after_create`, antes do provider; status `generating, generated(legado), approved, sent, failed, awaiting_approval, rejected`; índice parcial único `one_open_per_quote_request` (generating/approved/awaiting_approval) + `generate_correlation_id` único.
- Exceção no provider hoje deixa a versão presa em `generating` (sem sweeper; `RetryPolicy` só aceita `failed`, com `SAFE_RETRYABLE_REASONS = timeout network_error provider_unavailable`).
- Dados comerciais: `QuoteRequest#commercial` (jsonb, de `ResponseBlockParser`): `total_value` (string decimal), `schedule`, `scope`, `payment_terms` (obrigatórios) e `notes` (opcional). `ScanSolo::Quote::AmountInWords.call(BigDecimal)` dá o valor por extenso. Qualificação: `FieldResolver#make_qualification` (empresa, endereco_obra, cidade_uf, tipo_intervencao, area, profundidade, prazo_desejado, email, nome, telefone, projeto=cliente_final).
- Aprovação (`ApproveService`, sempre humana, exige `awaiting_approval`) e envio (`DeliveryService`, exige `document.attached?`, nunca chama Make) já existem.
- Storage: ActiveStorage (`ACTIVE_STORAGE_SERVICE`, `local` na VPS com volume `storage_data`).
- Infra: produção = Docker Compose na VPS (`docker-compose.production.yaml` + `docker-compose.scansolo.yaml`, rede default, sem `networks:`). **Gotenberg não existe no projeto**; foi a infraestrutura combinada com o desenvolvedor em 2026-10-09 (input de `scansolo-solicitacao-orcamento-email`, linha 13) e usada localmente para validar o template (`gotenberg/gotenberg:8.37.0`, `/forms/libreoffice/convert`).
- Gems: não há rubyzip nem lib de docx. Há `rest-client` (multipart), `nokogiri`, `pdf-reader`.
- Upload existente: `ScanSolo::KnowledgeSource has_one_attached :file` + `KnowledgeCenter.vue` (FormData). Não há tela de template.
- Nenhuma implementação parcial de `scansolo-proposta-template-local`.

## Decisões do desenvolvedor (2026-10-13, mensagem de abertura)

- Reutilizar obrigatoriamente: `Proposal`/`ProposalVersion`, `GenerateService`, `CallbackHandler`, `ApprovalRequestService`, `ApproveService`, `DeliveryService`, `RetryPolicy`, auditoria. Proibido: segundo fluxo, segunda tabela de proposta, segundo sistema de aprovação, segundo pipeline, chamadas paralelas.
- A resposta comercial é a fonte oficial de valor, prazo/cronograma, escopo/atividades, condições de pagamento e observações. Nenhuma IA gera preço, desconto ou condição; render 100% determinístico.
- Preservar idempotência, retry seguro, auditoria, isolamento por conta, versões, aprovação humana obrigatória, envio só após aprovação.
- Pipeline: template `.docx` → render determinístico → Gotenberg → PDF.
- Template nunca commitado (repo público; contém dados bancários/CNPJ): é enviado pelo sistema (upload) e guardado no ActiveStorage.
- Proibido durante a implementação: merge, deploy, migração em produção, envio de proposta real, alteração de segredos, Make.

## Decisões de desenho propostas (o router as assume; o clarifier pode contestar)

1. `ScanSolo::Proposal::LocalProvider.request_generation(...)` só enfileira `ScanSolo::ProposalLocalGenerationJob(version_id, correlation_id)` (fila `medium`); a conversão nunca roda dentro do `QuoteReplyJob` nem do request HTTP.
2. O job: revalida (versão `generating`, mesmo `generate_correlation_id`, `generate_callback_applied_at` vazio; senão no-op), renderiza o `.docx`, converte no Gotenberg, anexa o PDF em `document` (`<proposal_number>.pdf`, `application/pdf`, conferido com `pdf-reader` ou assinatura `%PDF`), e chama `CallbackHandler.apply_generate_result!(success: true, value: commercial total_value, currency: 'BRL', artifact_url: nil, artifact_sha256: SHA-256 do PDF, valid_until: data + 90 dias (prazo de validade fixo do template), template_version: "<id>:<sha256 do template>")`. O fluxo existente segue sozinho (aprovação por e-mail, botão Aprovar, envio).
3. Falhas nunca deixam `generating`: Gotenberg indisponível/timeout/5xx → até 2 novas tentativas do próprio job (30 s, 2 min) e depois `failed` com `provider_unavailable` via `CallbackHandler` (`success: false`); template ausente → `failed` com `template_unavailable`; dado obrigatório do template ausente ou render inválido → `failed` com `template_render_failed`. `template_unavailable` entra em `SAFE_RETRYABLE_REASONS` (depois do upload, o botão Reprocessar existente gera de novo). Nenhuma falha marca sucesso nem anexa PDF parcial.
4. `Integration`: modo local ativo quando `SCANSOLO_GOTENBERG_URL` está definido (variável de ambiente não secreta). Local tem precedência sobre Make: com a variável definida, `provider!` devolve `LocalProvider` e o Make nunca é chamado. `configured?`/`state` passam a considerar o modo local; o smoke `proposal_integration` só passa no modo local se a conta tiver template ativo.
5. Template: nova tabela pequena `scan_solo_proposal_templates` (account_id, `has_one_attached :file`, sha256, filename, uploaded_by, active; 1 ativo por conta, histórico preservado — não é tabela de proposta). Upload por API (admin, escopo da conta, 422 em arquivo inválido) e um cartão na tela de Propostas (`Proposals.vue`) para enviar/ver o template ativo, seguindo o padrão do `KnowledgeCenter.vue`. Validação no upload: `.docx` válido (zip com `word/document.xml`), ≤ 15 MB, todos os placeholders obrigatórios presentes e cada um inteiro dentro de um único `<w:t>`.
6. Placeholders (16) — `{{NUMERO_PROPOSTA}}`, `{{DATA_PROPOSTA}}`, `{{DATA_SOLICITACAO}}`, `{{NOME_EMPRESA}}`, `{{NOME_CONTATO}}`, `{{PROJETO_CLIENTE_FINAL}}`, `{{ENDERECO_OBRA}}`, `{{CIDADE_ESTADO}}`, `{{RUA_CIDADE_ESTADO}}`, `{{DESCRICAO_ESCOPO}}`, `{{PROFUNDIDADE}}`, `{{VALOR_NUMERICO}}`, `{{VALOR_EXTENSO}}` (os 13 do template v2) + `{{PRAZO_CRONOGRAMA}}`, `{{CONDICOES_PAGAMENTO}}`, `{{OBSERVACOES_COMERCIAIS}}` (novos, para a resposta comercial ser a fonte de prazo, pagamento e observações; o template v3 é preparado fora do repositório e aprovado visualmente pelo desenvolvedor).
7. Mapeamento determinístico (sem LLM):
   - NUMERO_PROPOSTA = `proposal_number`; DATA_PROPOSTA = data da geração por extenso pt-BR ("13 de outubro de 2026", tabela de meses fixa); DATA_SOLICITACAO = data de criação da oportunidade, mesmo formato.
   - NOME_EMPRESA = `empresa`; NOME_CONTATO = `nome`; PROJETO_CLIENTE_FINAL = `cliente_final`, senão `empresa`, senão `nome`.
   - ENDERECO_OBRA = `endereco_obra` (+ `bairro` quando não contido); CIDADE_ESTADO = `cidade_uf` como "Cidade – UF"; RUA_CIDADE_ESTADO = "<endereço>, em Cidade – UF" (só "Cidade – UF" sem endereço).
   - DESCRICAO_ESCOPO = `commercial.scope`; PRAZO_CRONOGRAMA = `commercial.schedule`; CONDICOES_PAGAMENTO = `commercial.payment_terms`; OBSERVACOES_COMERCIAIS = `commercial.notes` ou vazio.
   - VALOR_NUMERICO = `total_value` em pt-BR sem "R$" ("12.500,00", o template já tem "R$ "); VALOR_EXTENSO = `AmountInWords`.
   - PROFUNDIDADE = `profundidade`, senão `profundidade_intervencao`; ausente → ver pergunta ao desenvolvedor.
   - Valores escapados para XML; quebras de linha viram `<w:br/>`; caracteres de controle removidos; campo de qualificação ausente nunca é inventado.
8. Infra: serviço `gotenberg` (`gotenberg/gotenberg:8.37.0`, sem porta publicada, `restart: always`, healthcheck `/health`, logging do overlay) em `docker-compose.scansolo.yaml`; `SCANSOLO_GOTENBERG_URL=http://gotenberg:3000` no `.env.example` (documentado) e no ambiente de rails/sidekiq. Cliente HTTP: `rest-client` multipart (já no Gemfile), timeout explícito, sem SafeFetch (rede interna). Nova gem: `rubyzip` (leitura/escrita do `.docx`).
9. Make: `MakeProvider`, webhook e `MakeRequest` permanecem no código, sem alteração de comportamento; testes provam 0 `MakeRequest` e 0 HTTP para o Make no modo local.

## ACs confirmados (pedido do desenvolvedor)

1. Resposta válida gera exatamente 1 `ProposalVersion`.
2. Retry (job repetido, QuoteReplyJob reexecutado, Reprocessar) não duplica versão nem PDF.
3. PDF é persistido no ActiveStorage da versão (`document`), com SHA-256 registrado.
4. Falha de geração não marca sucesso (versão `failed`, sem PDF, auditoria `proposal.generation_failed`).
5. Aprovação humana continua obrigatória (versão fica `awaiting_approval`).
6. Envio ao lead não acontece antes da aprovação.
7. O fluxo posterior existente (e-mail de aprovação com PDF, Aprovar, `DeliveryService`, aviso, estágio) recebe o artefato local sem mudança.
8. O Make não é chamado pelo novo caminho.
9. (drafted) Upload de template inválido é recusado com 422 e não substitui o ativo.
10. (drafted) Smoke `proposal_integration` reflete o modo local (URL + template ativo).

## Docs a atualizar

`docs/agents/architecture.md`, `docs/agents/domain_rules.md`, `docs/agents/api_contracts.md`, `docs/agents/data_model.md`, `docs/architecture/SCANSOLO_DEPLOYMENT.md` (serviço gotenberg, variável, upload do template no roteiro).
