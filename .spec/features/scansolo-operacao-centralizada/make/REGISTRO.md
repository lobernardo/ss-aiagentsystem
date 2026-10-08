# Registro operacional — Make / Meta / Chatwoot (ScanSolo)

Evidências dos gates humanos da feature `scansolo-proposta-aprovacao-email` (Phases 15–18).
Regra: só registrar fatos verificados, com data. Segredos nunca entram aqui (no máximo hashes truncados).

## T38 — HG-D ampliado: backup de 8 cenários e estrutura de 2 data stores (RF-27)

Status: **backup concluído** (2026-10-08) — 10 arquivos válidos, conferidos e com scan de segredos limpo. Aprovação para T39/T40 registrada.

### Inventário confirmado (leitura via Make MCP, 2026-10-08)

Team `701134`, pasta `scanSolo` (`247121`). Nenhum cenário foi alterado, ativado, desativado ou executado.

| Cenário | Nome | Estado | Agendamento | Hook | Última edição |
|---|---|---|---|---|---|
| 6406463 | ScanSOLO_Proposta_Entrada | OFF (`isActive: false`) | immediately | 2859035 | 2026-09-25T20:52:38Z |
| 6177829 | Aprovacao_Gate_Processor | **ON** (`isActive: true`) | immediately | 2781008 | 2026-09-25T20:53:38Z |
| 6019491 | CRM_Agente_Proposta | **ON** (`isActive: true`) | on-demand | 2721577 | 2026-09-07T01:01:06Z |
| 6036802 | Lexus_ScanSolo_Proposta_v2 | **ON** (`isActive: true`) | immediately (100/min) | 2728200 | 2026-08-24T21:32:17Z |
| 6177833 | Aprovacao_Confirmada | OFF | on-demand | 2781009 | 2026-09-07T01:03:58Z |
| 5497443 | Aprovacao_Finalizar_Proposta | OFF | on-demand | 2755492 | 2026-08-31T16:56:04Z |
| 5325058 | Aprovacao_envia_proposta | OFF | on-demand | — | 2026-07-09T17:43:22Z |
| 5237984 | Proposta_automatizada | OFF | on-demand | — | 2026-07-10T01:01:24Z |

| Data store | Nome | Data structure | Registros | Usado por |
|---|---|---|---|---|
| 158313 | ScanSOLO_Config | 511342 | 1 | 6406463, 6177829 |
| 158314 | ScanSOLO_Proposta_Map | 511343 | 0 | 6406463, 6177829 |

### Arquivos de backup

| Arquivo | Origem | Status |
|---|---|---|
| `backups/datastore-158313-structure-20261008.json` | MCP `data-structures_get 511342` (só estrutura, 0 valores) | ✅ 2026-10-08; sha256 `547750f88ee4` |
| `backups/datastore-158314-structure-20261008.json` | MCP `data-structures_get 511343` (só estrutura, 0 valores) | ✅ 2026-10-08; sha256 `d490594a2ef2` |
| `backups/6406463-20261008.json` | Make UI → Export Blueprint (2026-10-08) | JSON válido; `name` = ScanSOLO_Proposta_Entrada; 27 módulos = `usedModules` do MCP; sha256 `eff5046795e5` |
| `backups/6177829-20261008.json` | Make UI → Export Blueprint (2026-10-08) | JSON válido; `name` = Aprovacao_Gate_Processor; 19 módulos = `usedModules` do MCP; sha256 `5bdaa8256bb3` (após redação; export original `f87fb8162331`) |
| `backups/6019491-20261008.json` | Make UI → Export Blueprint (2026-10-08) | JSON válido; `name` = CRM_Agente_Proposta; 6 módulos = `usedModules` do MCP; sha256 `39ffa7d7235f` (após redação; export original `ea62d00d02da`) |
| `backups/6036802-20261008.json` | Make UI → Export Blueprint (2026-10-08) | JSON válido; `name` = Lexus_ScanSolo_Proposta_v2; 66 módulos = `usedModules` do MCP; sha256 `19b569c577af` |
| `backups/6177833-20261008.json` | Make UI → Export Blueprint (2026-10-08) | JSON válido; `name` = Aprovacao_Confirmada; 4 módulos = `usedModules` do MCP; sha256 `5c0610903c7e` |
| `backups/5497443-20261008.json` | Make UI → Export Blueprint (2026-10-08) | JSON válido; `name` = Aprovacao_Finalizar_Proposta; 4 módulos = `usedModules` do MCP; sha256 `d1838049e97d` |
| `backups/5325058-20261008.json` | Make UI → Export Blueprint (2026-10-08) | JSON válido; `name` = Aprovacao_envia_proposta; 3 módulos = `usedModules` do MCP; sha256 `85a533f27fc7` |
| `backups/5237984-20261008.json` | Make UI → Export Blueprint (2026-10-08) | JSON válido; `name` = Proposta_automatizada; 7 módulos = `usedModules` do MCP; sha256 `8ff1edd99c79` |

### Scan de segredos

Comando do T38 nos 10 arquivos: `grep -lE "Bearer [A-Za-z0-9]|\"secret\"\s*:\s*\"[^{]|hook\.[a-z0-9]+\.make\.com/[A-Za-z0-9]"`.

- 2026-10-08, 2 estruturas: vazio.
- 2026-10-08, 10 arquivos: **2 ocorrências** do padrão `hook\.[a-z0-9]+\.make\.com/...` — URL de webhook do Make em texto puro (chave de 32 caracteres; valor não reproduzido aqui):
  - `6019491-20261008.json`: variável `finalize_webhook`.
  - `6177829-20261008.json`: variável `approval_url`.
- `5237984-20261008.json`: limpo — `Authorization: Bearer [REDACTED_SECRET_NOT_IN_BACKUP]`, `Client-Token` `<SCANSOLO_CLIENT_TOKEN>`, `instances/<SCANSOLO_ZAPI_INSTANCE>`, `token/<SCANSOLO_ZAPI_TOKEN>` (só placeholders).
- Demais blueprints: só referências a variáveis (`3.secret`, `2.inbound_bearer`, `{{...}}`), sem literal sensível.
- 2026-10-08, redação aprovada pelo desenvolvedor: a URL foi trocada por placeholder, 1 ocorrência por arquivo, JSON revalidado:
  - `6019491-20261008.json`: `finalize_webhook` → `<SCANSOLO_FINALIZE_WEBHOOK_URL>`.
  - `6177829-20261008.json`: `approval_url` → `<SCANSOLO_APPROVAL_WEBHOOK_URL>`.
- 2026-10-08, novo scan nos 10 arquivos e neste registro: **vazio**; nenhuma chave `make.com/<id>` restante.
- Restauração: ao reimportar 6019491, 6177829 ou 5237984, recolocar os valores reais no lugar dos placeholders (`<SCANSOLO_...>`, `[REDACTED_SECRET_NOT_IN_BACKUP]`) direto no Make.

### Conferência com o MCP (2026-10-08)

- `5325058`: módulos (3, ids/versões), `spreadsheetId`, conexão `9163373`, textos substituídos e agendamento idênticos ao `scenarios_get`.
- `6036802`: 66 ids de módulo na mesma ordem, hook `2728200`, ParseJSON `471185`, data stores `137401`/`137402`, arquivo e pasta do Drive, conexões `8175929`/`9163373`, `action_key`s e agendamento (immediately, 100/min) idênticos ao `scenarios_get`.

### Aprovação do desenvolvedor para T39/T40

2026-10-08 — **aprovado** pelo desenvolvedor (Leonardo), depois dos 10 arquivos conferidos e do scan limpo (commit `5f4bcd6559`).
Libera T39 (desativar, sem apagar, 6177829, 6036802, 6019491, 5497443 e 6177833) e T40 (adaptar a `Entrada` 6406463, mantida inativa).
Não libera a ativação da `Entrada` nem o deploy: os dois continuam presos à ordem do T41 (deploy → HG-03 → ativação).

## T39 — Make: desativar os legados, sem apagar (RF-28)

Status: **concluído** (2026-10-08).

Estado lido via Make MCP imediatamente antes (2026-10-08): ON = 6177829, 6019491, 6036802; OFF = 6177833, 5497443, 5325058, 5237984, 6406463 (igual ao inventário do T38).

| Cenário | Nome | Antes | Ação 2026-10-08 | Depois |
|---|---|---|---|---|
| 6036802 | Lexus_ScanSolo_Proposta_v2 | ON | `scenarios_deactivate` → "Scenario has been deactivated." | OFF |
| 6177829 | Aprovacao_Gate_Processor | ON | desativado pelo desenvolvedor na UI do Make (o `scenarios_deactivate` foi negado no Claude Code) | OFF |
| 6019491 | CRM_Agente_Proposta | ON | desativado pelo desenvolvedor na UI do Make (o `scenarios_deactivate` foi negado no Claude Code) | OFF |
| 6177833 | Aprovacao_Confirmada | OFF | nenhuma (já inativo) | OFF |
| 5497443 | Aprovacao_Finalizar_Proposta | OFF | nenhuma (já inativo) | OFF |
| 5325058 | Aprovacao_envia_proposta | OFF | nenhuma (já inativo) | OFF |
| 5237984 | Proposta_automatizada | OFF | nenhuma (já inativo) | OFF |

Listagem final via Make MCP (`scenarios_list`, team 701134, pasta 247121, 2026-10-08): os 8 cenários existem (`deleted: false`) e todos estão `isActive: false`: 6177833, 5325058, 5497443, 6177829, 6019491, 6036802, 5237984 e 6406463 (`Entrada`, ainda inativa). Os 7 legados estão OFF, 5325058 e 5237984 continuam inativos, e nenhum cenário foi apagado.
