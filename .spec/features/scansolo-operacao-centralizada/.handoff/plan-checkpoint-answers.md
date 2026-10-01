# Checkpoint do PLAN — respostas do desenvolvedor (2026-10-01)

Rodada 2 (padrões 1–6): confirmados.

- Q2 aceito: Rails gera `commercial.total_value_in_words` (determinístico, nunca IA) e envia ao Make. Atualizar CT-05/asyncapi.
- Q3 aceito: `initial_template_failure` visível na tela do lead, com motivo/status da falha de forma simples. Atualizar CT-02/openapi.
- Q4 texto final do aviso ao cliente (RF-53): "Recebi todas as informações, obrigado! Nosso comercial já está preparando seu orçamento. Assim que estiver pronto, envio por aqui." Enviado uma única vez ao entrar no estado de aguardando orçamento; nunca repetido em novos turnos.
- Q5 aceito: testes existentes só mudam de expectativa quando refletem mudança intencional prevista no SPEC; nunca flexibilizar para passar; atualizar apenas os incompatíveis com os novos requisitos.
- Q6 opção (b): ação/comando de reenvio manual da solicitação de orçamento (casos: inbox mal configurado, falha temporária, config corrigida depois, necessidade de reenviar ao Luciano). Manual, auditado e idempotente; nunca cria segunda solicitação paralela quando já existe uma válida em andamento (reenvia a mesma solicitação/correlação). Expor como endpoint + ação na tela do lead (e/ou rake), com permissão de admin.

Ajustes adicionais:
1. Destinatário comercial configurável: `comercial@scansolo.com.br` deixa de ser hardcoded; vira campo da configuração existente (ao lado de inbox de orçamento e usuário comercial), valor inicial `comercial@scansolo.com.br`, sujeito ao snapshot de publicação como os outros dois.
2. Remoção de aprovar/enviar legado: sair do fluxo ativo primeiro (ocultar/desativar na UI e no fluxo novo). Antes de remover rotas/endpoints/código, validar que nenhuma tela, job, integração (incl. Make), histórico ou fluxo legado depende deles; a remoção definitiva só acontece com ausência de uso comprovada (task de verificação com evidência registrada; se houver dependência, manter desativado e não remover).
