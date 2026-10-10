# Input — scansolo-solicitacao-orcamento-email

Origem: modelo de e-mail aprovado pelo Leo em 2026-10-09 (exemplo AMAGGI), confirmado no checkpoint do /plan. Repositório público: o exemplo abaixo usa dados fictícios no lugar de e-mail/telefone reais.

## Contexto do código (verificado)

- E-mail atual de solicitação de orçamento: `ScanSolo::Quote::EmailComposer.request` (CT-03) chamado por `ScanSolo::Quote::RequestService` (RF-12..RF-15, RF-22, RF-53 de `.spec/features/scansolo-operacao-centralizada/SPEC.md`). Enviado pelo inbox de e-mail nativo (`ScanSolo::Quote::Mailbox`, `EmailThread`), destinatário da config publicada (RF-54), idempotente (1 `QuoteRequest` por oportunidade), auditado (`quote_request.sent`). Termina com o bloco CT-04 lido por `ScanSolo::Quote::ReplyProcessor` / `ResponseBlockParser`. Reenvio manual: `ScanSolo::Quote::ResendService` (RF-56/CT-12).
- Campos: `ScanSolo::Qualification::FieldResolver::CATALOG` (`app/services/scan_solo/qualification/field_resolver.rb`), projeção `ScanSolo::LeadState::Projection`.
- Textos em `scan_solo.*` (I18n, RNF-08).

## Decisões do desenvolvedor (2026-10-09)

- Escopo: só o e-mail (Fase A). Geração local do PDF no template (.docx + Gotenberg) fica para outra feature (`scansolo-proposta-template-local`), condicionada ao OK do Luciano. Se a proposta automática não ficar boa, Luciano usa os dados do e-mail e envia manualmente.
- MANTER o bloco de resposta CT-04 no final do e-mail novo (Luciano responde com valor/prazo/escopo/pagamento → ReplyProcessor).
- Nome de exibição do remetente: "Atendimento Comercial ScanSolo". E-mail do canal continua `atendimento.comercial@scansolo.com.br`.
- Sem Reply-To novo: a resposta volta ao thread da caixa de cotação.
- Anexos do lead: anexar até limite total (~15 MB); acima, listar nomes + link da conversa no ScanSOLO.
- Parágrafo de modo validação: flag de config, ligado por padrão até ser desligado.
- Link "Abrir no ScanSOLO"/conversa: manter (já existe).
- Rótulos de serviço iniciais: georadar/GPR → "GeoRadar", pipe locator → "Pipe Locator", combinado → "GeoRadar + Pipe Locator"; sem rótulo → texto livre coletado, nunca vazio.

## ACs confirmados

1. Assunto `Solicitação de orçamento | {empresa_curta} | {servico_label} | {cidade}/{uf}`; sem cidade/UF omite o trecho (sem `|` solto); sem quebras de linha; ≤ ~120 chars truncando empresa_curta primeiro.
2. Corpo nas seções do modelo; linhas opcionais vazias omitidas; texto do lead citado sem reescrita; HTML escapado.
3. Pendências = obrigatórios sem valor ∪ opcionais do tipo de serviço (tabela de config, não LLM); parágrafo final varia com/sem pendências.
4. Localização normalizada para link Google Maps; links do mesmo ponto (< ~50 m) deduplicados; pontos distintos listados rotulados.
5. Bloco CT-04 preservado no fim; leitura da resposta continua funcionando.
6. Parágrafo "modo validação" só com a flag ligada (padrão ligado).
7. Anexos do lead até 15 MB total; acima, lista + link da conversa.
8. E-mail "Atualização:" no mesmo thread quando o lead complementa dados após o envio: só mudanças + resumo completo; 1 por versão da qualificação.
9. Remetente "Atendimento Comercial ScanSolo"; sem preço/estimativa/prazo prometido/menção a IA ou sistema/segredos.
10. Falha de envio → nota privada + retry limitado; handoff humano não bloqueado.

## Modelo do e-mail (texto-base)

Assunto: `Solicitação de orçamento | {empresa_curta} | {servico_label} | {cidade}/{uf}`
- empresa_curta: nome de marca, removendo sufixos societários (Ltda., S.A., EIRELI, ME, "Exportação e Importação" etc.); ambíguo → razão social inteira; sem fonte externa.

Corpo (`[[SE x]]...[[/SE]]` = só aparece se o campo existir):

```
Olá, Luciano.

Segue uma nova solicitação de orçamento recebida pelo atendimento comercial da ScanSolo.
[[SE modo_validacao]]Nesse primeiro momento estou aprendendo como automatizar a construção deste template, então você pode olhar como está ficando para irmos validando.[[/SE]]
No geral, seguem os dados coletados do lead:

DADOS DO CLIENTE
Empresa: {empresa_razao_social}
[[SE cnpj]]CNPJ: {cnpj}[[/SE]]
Contato: {nome_contato}   [[omitir se vazio]]
E-mail do solicitante: {email}
Telefone/WhatsApp do solicitante: {telefone | "não informado"}

LOCAL DO SERVIÇO
[[SE unidade]]Unidade: {unidade}[[/SE]]
Endereço informado: {endereco_obra}
[[SE localizacao_url]]Localização informada pelo cliente (Google Maps): {localizacao_url}[[/SE]]

SERVIÇO SOLICITADO
{servico_descricao}

OBJETIVO DO LEVANTAMENTO
{objetivo_servico}

[[SE area_extensao OU profundidade OU prazo OU integracao_seguranca]]
DETALHES TÉCNICOS INFORMADOS
[[SE area_extensao]]Área/extensão: {area_extensao}[[/SE]]
[[SE profundidade]]Profundidade de interesse: {profundidade}[[/SE]]
[[SE prazo]]Prazo desejado: {prazo}[[/SE]]
[[SE integracao_seguranca]]Integração de segurança: {integracao_seguranca}[[/SE]]
[[/SE]]

DOCUMENTAÇÃO RECEBIDA
[[SE anexos]]- {nome_arquivo} ({tipo}) — anexado a este e-mail.[[/SE]]
[[SE NÃO anexos]]Nenhum documento recebido até o momento.[[/SE]]

[[SE pendencias]]
INFORMAÇÕES AINDA NÃO CONFIRMADAS
* {item};
[[/SE]]

[[SE pendencias]]
Peço, por favor, que avalie a documentação e as informações disponíveis para verificarmos se já é possível estruturar o orçamento ou se precisamos retornar ao cliente solicitando algum dado técnico adicional.
[[SENÃO]]
Os dados obrigatórios estão completos. Peço, por favor, que avalie a documentação para estruturarmos o orçamento.
[[/SE]]

Atenciosamente,
Comercial ScanSolo

[bloco de resposta CT-04 mantido aqui]
```

## Regras de geração

- Telefone = telefone do contato Chatwoot (WhatsApp); o agente nunca pergunta. "não informado" só se o contato não tiver número.
- Pendências: rótulos fixos — "Área/trecho exato e dimensões a serem varridas", "Profundidade-alvo de investigação", "Necessidade e condições de integração de segurança", "Liberações necessárias para acesso e execução", "Prazo/urgência", "Fotos atuais do local", "KMZ/KML da área, se disponível", "Requisitos específicos de entrega". Conjunto opcional por tipo de serviço vem de configuração.
- Localização: `https://www.google.com/maps?q={lat},{lng}` (6–7 casas). Links diferentes para o mesmo ponto → só o primeiro; pontos distintos (> ~50 m) → todos, rotulados. Pin do WhatsApp entra como link de mapa. Endereço cadastral + link → ambos, em linhas separadas.
- Texto livre do lead (objetivo, unidade, endereço): citado sem reescrever/completar. Resumo do LLM só se o campo vier vazio mas a conversa o responder; nesse caso marcar "(extraído da conversa)".
- Proibido: preço, estimativa, desconto, prazo prometido, link inventado, menção a IA/sistema/falha técnica, segredos.
- Segurança: escapar HTML de todo campo do lead; remover quebras de linha dos campos do assunto (anti header-injection); só URLs https de mapas conhecidas como link clicável.
- Nunca enviar dado inventado; campo ausente = não informado/omitido.
- Renderizador determinístico em Rails; o LLM não escreve o e-mail.
- Auditoria: opportunity_id, versão do template, destinatário, message_id, resultado.

## Exemplo (fictício, baseado no caso AMAGGI)

Assunto: `Solicitação de orçamento | AMAGGI | GeoRadar | Lucas do Rio Verde/MT`
Entradas: empresa "AMAGGI Exportação e Importação Ltda."; cnpj presente; e-mail do solicitante presente; telefone vazio; unidade "AMAGGI – Lucas do Rio Verde/MT"; endereço com rodovia, bairro e CEP; localização -13.0053596,-55.9400673 (segundo link do mesmo ponto descartado); serviço GeoRadar/GPR; objetivo "localizar tubulações enterradas…"; 1 anexo (planta executiva); sem área, profundidade, prazo, integração, fotos, KMZ → 8 pendências.

## Testes esperados

Assunto sem cidade/UF; sem pendências; com/sem anexos; acima do limite de anexos; campo com HTML/quebra de linha; dois links de mapa iguais e distintos; reenvio idempotente; e-mail de atualização; modo validação on/off; leitura do bloco CT-04 inalterada.

## Docs a atualizar na implementação

BACKLOG.md (F2-04), DECISOES.md (nova DEC: e-mail ao comercial determinístico + formato de assunto), claude/PLANO_AGENTE_E_PROPOSTAS.md (§9), STATUS_ATUAL.md, CHANGELOG.md, SYSTEM_MAP.md — quando existirem no repo.
