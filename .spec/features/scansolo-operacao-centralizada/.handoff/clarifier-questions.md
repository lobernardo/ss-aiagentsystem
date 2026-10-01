# Clarifier — rodada 1 (SPEC v1.0, pendente de respostas do desenvolvedor)

Recomendada = (a) em todas.
- Q-01 RF-26/CT-05/CT-06: número da proposta e validade. (a) Rails gera número e persiste valid_until; (b) Make gera e devolve no callback; (c) só id da versão.
- Q-02 CT-03/CT-04: e-mail nativo junta linhas (CommonMark sem hardbreaks). (a) HTML com quebras + parser tolerante + ignora bloco vazio citado; (b) gramática estrita; (c) anexo/formulário.
- Q-03 RF-48/29/30: PDF público e `sent` falso em falha assíncrona da Meta. (a) Rails baixa o PDF, guarda no ActiveStorage e usa URL própria; falha posterior marca versão failed + auditoria sem reverter etapa; (b) Drive público aceitando risco; (c) storage com URL assinada pelo Make.
- Q-04 RF-28/29: toggle require_proposal_approval + botões aprovar/enviar viram caminho duplicado. (a) remover approve/send e proposal.send, ocultar toggle; (b) manter só para legado; (c) manter.
- Q-05 RF-12: quando dispara o orçamento. (a) só com próxima ação `proposta`; (b) toda conclusão; (c) lista configurável.
- Q-06 RF-35: etapas do sinal de negociação. (a) só proposta_enviada/negociacao; (b) qualquer etapa; (c) antes da proposta só handoff.
- Q-07 RF-23: nova resposta do Luciano após uma validada. (a) pendente para decisão manual; (b) nova versão + reenvio automático; (c) ignorar.
- Q-08 RF-43: tentativas restantes após resposta. (a) cancela só a próxima, no máx. 1 por ciclo, mantém horários; (b) recalcula a partir da resposta; (c) (a) sem limite.
- Q-09 RF-09/CT-01: contato com oportunidade aberta no "Novo lead". (a) 422 + abrir a existente; (b) reaproveitar e só enviar template; (c) criar outra.
- Q-10 RF-02: origem de conversa aberta por humano pela via nativa. (a) 1ª msg incoming → site, 1ª outgoing humana → manual; (b) sempre site; (c) vazio.

Lacunas sem pergunta formal:
- O que o cliente ouve entre qualificação e proposta (pode levar dias).
- Onde o operador configura o inbox de e-mail de orçamento e o usuário do Luciano (sem UI hoje).
- Escopo extra a confirmar/cortar: `qualification.projeto` no CT-05; valor por extenso (RF-47); retry só do WhatsApp (CT-10).
- Contato com conversa aberta no inbox mas sem oportunidade, no "Novo lead".
