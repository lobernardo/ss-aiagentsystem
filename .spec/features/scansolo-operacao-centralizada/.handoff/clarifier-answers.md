# Clarifier answers — rodada 1 (desenvolvedor, 2026-10-01)

- Q-01 (a): Rails gera o número da proposta e persiste a validade (valid_until); o Make recebe esses dados para montar o documento.
- Q-02 (a): e-mail em HTML preservando quebras de linha; parser tolerante a pequenas variações, guiado pelos rótulos, ignorando o bloco vazio citado da mensagem original. Rótulos aprovados: "Valor total", "Prazo/cronograma", "Escopo/atividades", "Condições de pagamento", "Observações comerciais" (opcional).
- Q-03 (a): sem link público permanente. Rails baixa/recebe o PDF gerado, armazena no Chatwoot/ActiveStorage e envia a partir dali pelo fluxo nativo do WhatsApp. `sent` só após confirmação real do transporte; falha → `failed` + auditoria (sem reverter etapa, conforme recomendação).
- Q-04 (a): sem segunda aprovação. Remover/ocultar da operação ScanSolo os botões Aprovar/Enviar e o toggle de aprovação obrigatória do fluxo antigo, sem prejudicar dados históricos. Make não faz etapa de envio ao cliente: Make gera, Chatwoot envia.
- Q-05 (a): solicitação ao Luciano só com qualificação completa E próxima ação vigente = `proposta`. Nunca em dúvida, consulta técnica, localização de rede ou atendimentos sem proposta.
- Q-06 (a): sinal de negociação só em `proposta_enviada` e `negociacao`; antes disso o agente mantém a política atual.
- Q-07 (a): nova resposta do Luciano após uma já aceita/aplicada → pendente para decisão manual (inclusive durante `generating`); sem nova versão nem reenvio automático.
- Q-08 (a): resposta do cliente cancela a tentativa pendente imediata, no máximo 1 cancelamento por ciclo (sem novo cancelamento até a próxima mensagem de saída), horários das demais mantidos; sem recalcular a cadência; comportamento previsível e auditável (registrar auditoria do cancelamento).
- Q-09 (a): "Novo lead" para contato com oportunidade não terminal → 422 `opportunity_exists` com id; UI oferece abrir a existente.
- Q-10 (a): conversa fora do "Novo lead": 1ª interação inbound do cliente → SITE/WHATSAPP; conversa iniciada por humano da equipe (1ª mensagem outgoing humana) → COMERCIAL.

## Lacunas
1. Espera entre qualificação e proposta: após enviar a solicitação ao Luciano, o agente avisa UMA única vez ao cliente que as informações foram recebidas e o comercial está preparando o orçamento; durante a espera segue respondendo dúvidas normalmente, sem repetir o aviso.
2. Configuração: dois campos na configuração existente (sem tela nova): inbox de e-mail usado para orçamento; usuário comercial responsável (Luciano), opcional.
3. Escopo extra:
   - `qualification.projeto`: manter — o cenário Make atual (`ScanSOLO_Proposta_Entrada`) lê `qualification.projeto` para o placeholder `{{PROJETO_CLIENTE_FINAL}}` (levantamento em `.spec/features/scansolo-proposal-request-e2e/.handoff/confirmed-input.md`). Se o cenário adaptado deixar de usar, cortar.
   - Valor por extenso: manter, gerado de forma determinística pelo sistema ou pelo Make, nunca pela IA.
   - Retry: manter retry específico para falha real de entrega do documento/mensagem WhatsApp, sem repetir a geração quando o PDF já existe.

## Reforços pedidos para o SPEC
- Preservar o agente atual; não alterar treinamento, base de conhecimento e configuração publicada sem necessidade direta.
- Chatwoot nativo sempre que possível; reaproveitar serviços ScanSolo existentes.
- Toda remoção de fluxo legado compatível com histórico e sem quebrar produção.

# Rodada 2 — padrões aplicados pelo router (desenvolvedor autorizou fechar o SPEC; confirmar no checkpoint do PLAN)
1. valid_until: o Make continua calculando a validade (`validade_dias` do ScanSOLO_Config) e o Rails persiste o `valid_until` do callback. Schema do callback inalterado.
2. Origem: primeira mensagem outgoing automática/campanha (não humana) fora do "Novo lead" → origem vazia ("Não informada"). O backfill (RF-03) aplica a mesma regra do RF-02 com evidência: 1ª mensagem incoming do cliente → `website`; 1ª mensagem outgoing de usuário humano → `manual`; demais → vazio.
3. RF-23 decisão manual: nesta versão o operador só pode "descartar" a resposta pendente (com auditoria). Aplicar uma resposta tardia como revisão de proposta fica para evolução futura (revisões continuam manuais fora do fluxo automático).
4. RF-32: falha no download do PDF = falha de entrega (`artifact_download_failed`), com retry de entrega sem nova geração — confirmado.
5. RF-43: o ciclo reinicia com qualquer mensagem outgoing não privada — confirmado.
6. "Novo lead" para contato que já tem conversa aberta no inbox WhatsApp oficial mas sem oportunidade: reaproveitar essa conversa (sem criar outra), criar a oportunidade com origem `manual` em `novo_lead` e enviar o template inicial.
