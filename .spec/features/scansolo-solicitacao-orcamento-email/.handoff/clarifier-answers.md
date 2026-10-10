# Clarifier answers — 2026-10-10 (developer accepted all recommendations)

- M-01: "Unidade" = CATALOG `cliente_final` (linha "Unidade / cliente final"); sem chave nova.
- M-02: sem `tipo_servico` nem `tecnologia` → rótulo "Serviço não informado" no assunto/corpo e item "Tipo de serviço" nas pendências.
- M-03: nova seção "OUTRAS INFORMAÇÕES" (antes de DOCUMENTAÇÃO RECEBIDA) listando, com o label do CATALOG, só as chaves preenchidas que não têm lugar no modelo; vazias omitidas.
- M-04: pendência "Liberações necessárias para acesso e execução" satisfeita por `restricoes_acesso` OU `documentacoes_necessarias`; "Requisitos específicos de entrega" satisfeita por `condicoes_especiais`.
- M-05: e-mail de atualização só enquanto a solicitação está aguardando resposta (Luciano ainda não respondeu com o bloco processado); mudanças agrupadas por janela de 10 minutos (debounce) → 1 e-mail por janela; idempotente por opportunity + versão da qualificação.
- M-06: retry de envio: 3 tentativas após 1, 5 e 15 minutos; esgotadas → nota privada na conversa do lead + evento de auditoria; handoff não bloqueado.
- M-07: flag `modo_validacao` na mesma config publicada do destinatário comercial (OC/RF-54), com toggle na mesma tela (padrão ligado). Tabela de pendências opcionais por tipo de serviço e mapa de rótulos de serviço: arquivo de configuração versionado no código (não secreto), sem UI.
- M-08: remover o resumo por LLM "(extraído da conversa)": campo vazio é omitido/vira pendência; renderização 100% determinística a partir dos dados coletados.
- M-09: "Atualização:" na primeira linha do corpo; assunto segue o threading nativo "Re: <mail_subject>".

# Round 2 — 2026-10-10

Developer context: the agent already keeps asking until the lead sends everything or says he doesn't have it; the e-mail to Luciano goes ONCE, after collection ends, with whatever exists. Post-send complements are an edge case.

- M-10: fixed 10-minute window opened by the first change after send (not a restarting debounce); 1 update e-mail per window; still only while awaiting_reply/correction_requested. Keep the update path minimal — it is an edge case, not the main flow.
- M-11: no automatic retry when the native message was created and later marked `failed` (avoids duplicate e-mails); post private note + audit event immediately; manual resend (OC/RF-56) remains. Retry 1/5/15 min applies only to failures before the message is created.
- Cidade/UF: also in the body — line "Cidade/UF: {cidade_uf}" in LOCAL DO SERVIÇO below the address (omitted if empty). Body carries all collected information (subject keeps cidade/UF too).
- Interpretations confirmed: M-05 statuses `awaiting_reply` or `correction_requested`, checked at send time; M-01 line label "Unidade / cliente final:".
