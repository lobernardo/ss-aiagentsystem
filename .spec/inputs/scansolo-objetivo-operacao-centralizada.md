# Objetivo — operação ScanSolo centralizada no Chatwoot (diretriz do desenvolvedor, 2026-10-01)

## Objetivo
Centralizar toda a operação comercial e de atendimento da ScanSolo dentro do Chatwoot, aproveitando o que já está funcionando. O Chatwoot será o sistema principal da operação, concentrando: WhatsApp oficial; atendimento por IA; atendimento humano; contatos; conversas; pipeline comercial; qualificação dos leads; cadências; follow-ups; propostas; tarefas operacionais; indicadores. A operação deve funcionar dentro de um único ambiente.

O Chatwoot continuará responsável pelo atendimento e pelas automações já existentes e receberá apenas as funcionalidades comerciais necessárias para a operação da ScanSolo.

**Restrição:** a API oficial do WhatsApp já está configurada e o agente já está funcionando e treinado — não mexer nisso.

## 3. Origem dos leads
### 3.1 Lead vindo do site/WhatsApp
Site / WhatsApp → Chatwoot → contato/conversa → agente de IA → qualificação → pipeline → cadência correspondente. Origem: Site.

### 3.2 Lead cadastrado pelo comercial
O usuário da ScanSolo deverá conseguir cadastrar um lead manualmente dentro do próprio Chatwoot (como já tem a opção lá dentro). Ao salvar, o sistema deverá: verificar se o contato já existe; evitar duplicidade; criar ou vincular o contato; criar o lead; registrar a origem; inserir o lead na etapa escolhida; inserir o lead na cadência correspondente. Origem: Cadastrado pelo comercial.

## 4. Campo de origem
Informação estruturada do lead (`lead_source`). Valores iniciais: `website`, `manual`. Na interface: "Site", "Cadastrado pelo comercial". Pode existir tag visual no pipeline. A origem serve apenas para identificação, filtros e indicadores; não altera o funcionamento das cadências.

## 5. Pipeline comercial
Continua no menu customizado ScanSolo. Estrutura inicial: Novo Lead → Em Contato → Em Qualificação → Qualificado → Proposta Enviada → Negociação → Ganho / Perdido. As etapas definitivas devem respeitar o fluxo operacional já definido.

## 6. Card do pipeline
Empresa; Contato; Serviço; Cidade/UF; Origem; Responsável; Etapa atual; Última interação; Status da cadência; Tentativa atual; Próximo follow-up; Tempo sem interação; Status da proposta. Indicação visual como "Sem interação há 2 dias". Origem clara: SITE ou COMERCIAL.

## 7. Tela do lead
Dados básicos: nome; empresa; telefone; e-mail; origem; responsável; etapa.
Dados de qualificação (variam conforme o serviço). Para GPR: tipo de serviço; extensão/metragem; área; profundidade; tipo de piso; endereço da obra; cidade/UF; data; turno; contato de campo; restrições; necessidade de ART; documentos necessários; demais informações técnicas.

## 8. Estado estruturado do lead
Cada lead possui estado estruturado: origem; serviço; estágio; dados coletados; dados faltantes; responsável; status de qualificação; status da proposta; status da cadência; tentativa atual; próxima tentativa; última interação. O agente consulta e atualiza esse estado; evita repetir perguntas.

## 9. Cadências
Executadas dentro do Chatwoot. Entrada automática (agente/sistema move o lead de etapa) ou manual (comercial cadastra lead e seleciona etapa/cadência). Ex.: comercial cadastra lead → seleciona "Em Contato" → sistema registra → cadência "Em Contato" iniciada.

## 10. Regras das cadências
Respeitam o comportamento já definido. As cadências já estão configuradas e são configuradas no Chatwoot.

## 11. Resposta do cliente
Cliente responde → Chatwoot recebe → estado do lead atualizado → cadência interrompida ou recalculada conforme regra → última interação atualizada → pipeline reflete. Não continuar enviando follow-ups indevidamente após resposta.

## 12. Handoff humano
Agente IA → handoff → humano assume → automação pausada conforme regra. Permitir: pausar; encerrar; reabrir; devolver para automação quando aplicável. Identificar claramente quando a conversa está sob atendimento humano.

## 13. Menu ScanSolo
Ajeitar visualmente o menu ScanSolo com o que já foi mapeado. Organização aproximada: Pipeline; Leads; Propostas; Tarefas; Relatórios; Automações; Configurações. A conversa continua na interface normal do Chatwoot; o menu ScanSolo é a camada operacional e comercial.

## 14. Arquitetura final desejada
Chatwoot → WhatsApp oficial → Contatos → Conversas → Agente de IA → Qualificação → Handoff humano → Pipeline ScanSolo → Leads → Cadastro manual de leads → Cadências → Follow-ups → Propostas → Tarefas → Relatórios. Tudo dentro da mesma aplicação.
