# Aprovação — scansolo-escalacao-filtrada (T01)

> Rascunho. Pendente de aprovação do Leo. Enquanto a linha de aprovação não existir, nenhuma fase seguinte do PHASES.md é executada.

## Nova DEC

- Id: DEC-060 (confirmada contra DECISOES.md, última era DEC-059)
- Título: Escalação filtrada ao Artur — e-mail primeiro, `wa.me` só para lead qualificado, com orçamento enviado, que insiste após orientação por e-mail
- Data: 16/11/2026

## Redação aprovada (`scan_solo.commercial.email_first.*`)

`%{email}` = `quote_recipient_email` publicado; `%{fields}` = rótulos dos campos elegíveis faltantes.

### `before_qualified`

Os valores e prazos vêm na proposta que o nosso comercial envia por e-mail assim que eu concluir o seu atendimento. Se quiser, pode escrever para %{email}.

### `before_qualified_ask`

Os valores e prazos vêm na proposta que o nosso comercial envia por e-mail assim que eu concluir o seu atendimento. Se quiser, pode escrever para %{email}. Para seguir, me informe: %{fields}.

Regra (RF-02): no modo progressivo, `%{fields}` contém no máximo 2 campos faltantes por mensagem (1 ou 2); no modo `em_bloco`, contém todos os campos relevantes pendentes. Em ambos os modos, nunca campo já confirmado.

### `quote_pending`

Seu pedido de orçamento segue para o Artur, do nosso comercial. Valores e prazos chegam na proposta por e-mail; se quiser, pode escrever para %{email}.

### `quote_sent`

Seu pedido de orçamento já está com o Artur, do nosso comercial. Valores e prazos chegam na proposta, por e-mail, no endereço que você informou. Se quiser falar antes disso, pode escrever para %{email}.

### Entrega do link (insistência elegível)

Reutiliza `scan_solo.negotiation.escalation_reply`, sem mudança.

Aprovado por: Leo
