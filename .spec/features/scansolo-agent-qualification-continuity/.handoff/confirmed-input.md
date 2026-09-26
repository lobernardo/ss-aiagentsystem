# Confirmed input — scansolo-agent-qualification-continuity

Summary: Resolvedor canônico e determinístico de campos de qualificação (ScanSolo::Qualification::FieldResolver) + regras fixas de continuidade no PromptBuilder.
Tier: standard. Source description: .spec/inputs/scansolo-agent-qualification-continuity.md

## Acceptance criteria (confirmed by developer — source of truth)
1. Resolvedor retorna, por campo obrigatório, valor + origem (native|custom_attribute) + satisfeito?; nome/e-mail/telefone mapeiam para contact.name/contact.email/contact.phone_number.
2. Chaves comparadas normalizadas (trim, case-insensitive, sem acento, `_`/espaço/`/` equivalentes) + aliases. Mapa canônico explícito (rótulo config v2 / aliases -> chave canônica):
   - "Nome" / "nome completo" / "name" -> nome (nativo contact.name)
   - "Telefone" / "WhatsApp" -> telefone (nativo contact.phone_number)
   - "E-mail" / "email" -> email (nativo contact.email)
   - "Objetivo do serviço" / "tipo de intervenção" / "escopo" -> tipo_intervencao
   - "Cidade / UF" / "cidade" -> cidade_uf
   - "Endereço da obra" / "endereço" -> endereco_obra
   - "Área ou extensão" / "área" / "area_total" -> area
   - "Profundidade de interesse" / "profundidade" -> profundidade
   - "Prazo desejado" / "prazo" / "urgência" -> prazo_desejado
   - "Empresa" / "razão social" / "company" -> empresa
   - "Integração de segurança" -> integracao_seguranca (sem equivalente no Make; só qualificação)
3. Os 6 consumidores (ai_turn/context_assembler, actions/qualification_field_action, cadence/reply_completeness_detector, proposal/generate_service, proposal/make_provider, handoff/handoff_service) usam só o resolvedor e retornam o mesmo resultado para o mesmo contato.
4. qualification_field aceita chaves normalizadas/aliases, grava todas as reconhecidas de uma vez (captura múltipla), não sobrescreve campo nativo já preenchido, e registra chave não reconhecida na evidência da ação.
5. PromptBuilder injeta 3 regras fixas (não editáveis pelo config), antes das regras do config: (1) nunca perguntar de novo informação já presente no contato/campos/histórico; (2) responder primeiro à pergunta/intenção atual, depois pedir no máximo um campo faltante; (3) cumprimentar só na primeira resposta da conversa. E instrui registrar todos os dados informados via qualification_field.
6. missing_fields não contém Nome/E-mail quando os nativos existem.
7. make_provider envia `qualification` com as chaves canônicas (empresa, endereco_obra, cidade_uf, tipo_intervencao, area, profundidade, prazo_desejado, email, nome, telefone), preenchidas pelo resolvedor, independentemente do rótulo usado na config. Spec: com a config v2 publicada (rótulos em português), o payload ao Make contém essas chaves com os valores gravados.
8. Sem mudança de contrato CT-01..CT-11 (exceto expor opcionalmente a origem do campo no detalhe da oportunidade), sem migration destrutiva, sem dependência de enterprise/ ou Captain::. Aliases em constante (preferido) ou jsonb aditivo — decidir no PLAN.
9. `# rubocop:disable Rails/SkipsModelValidations` inline em spec/services/scan_solo/knowledge/ingestion_service_spec.rb (linha do update_columns do teste CRLF).
10. Specs: resolvedor; ação (captura múltipla, não sobrescreve nativo, chave desconhecida na evidência); contexto/prompt (3 regras fixas; missing_fields sem Nome/E-mail com nativos); consistência dos 6 consumidores; oportunidade com dados sob rótulos antigos/alternativos é reconhecida via alias (não aparece em missing_fields); integração mock LLM (lead com nome + pergunta técnica -> sem pergunta de nome; resposta parcial; dados fora de ordem; retorno após handoff); regressão ./scripts/ralph-test.sh verde.
