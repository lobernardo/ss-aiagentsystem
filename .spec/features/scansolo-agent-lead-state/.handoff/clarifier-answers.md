# Clarifier answers — developer, 2026-09-29 (all recommended options)

Q-01 (M1, M2; RF-15, RF-21, RF-23) → A.
One required set for all intents: `required_qualification_fields` from the published config stays the source. Every other catalog field is complementary.
Intent sets only the default next action and one script line in the prompt:
- orcamento / convite_cotacao → proposta
- avaliacao_tecnica / visita / localizar_rede → avaliacao_tecnica
- envio_documentos → solicitar_documentos
- acompanhar_proposta / duvida / verificar_capacidade / outro / null → aguardar_cliente
Stages stay the current 8. Completion always goes to `qualificado`. A completed qualification does not reopen.
If the model sends no `next_action` on the completion turn, the intent's default next action applies. Completion is never deferred.

Q-02 (M4, M5; RF-05, RF-11) → A.
One model call per turn. Actions are persisted in a transaction, the validator runs over the new state, and the transaction rolls back on block.
One regeneration, with the violation fed back to the model. If it fails again, the turn is `failed` with no message (current behavior).
Lexical detection (RF-11 b) applies only to labels/aliases with ≥2 tokens, or to the model's own `asked_fields`.

Q-03 (M6; RF-01, RF-08) → A.
An additive rake/migration backfill creates the state for all existing opportunities.
Contact values (native + custom_attributes, including the WhatsApp profile name) enter as `inferido`, and the agent asks for confirmation.
Writes stay mirrored to Contact `custom_attributes`.

Q-04 (M3; RF-17, RF-19) → A.
Text extraction with a pure-Ruby gem (`pdf-reader`), no model call, limited to 10 pages and 10 MB.
A scanned PDF with no text falls into RF-20 (reason recorded, no OCR).
Text links are never fetched over HTTP. A map URL (Google Maps, goo.gl/maps, maps.app.goo.gl) becomes `link_local` with status `inferido`. Other links are only visible to the model and fill no field.

Safe defaults accepted:
- M7 (RF-24, RF-25): enforced by the prompt only, via a deterministic "summary allowed/not allowed" indicator plus the list of authorized actions. No new validator violation.
- RF-09: within each required/complementary group, fields follow the RF-02 table order.
- RF-19 vs RF-05: on a `failed` turn, fields extracted from a PDF are reverted too (same all-or-nothing).

## Round 2 — developer, 2026-09-29 (after planning; PLAN Open Question Q7/Q1)
Backfill (RF-01, RF-08): opportunities whose current stage is `qualificado` or later (`qualificado`, `proposta_enviada`, `negociacao`, `ganho`, `perdido`) get a qualification state marked `concluida`.
- Contact-derived values are still seeded as `inferido`.
- The agent does not requalify these opportunities.
- The proposal gate is not blocked by the inferred status for them.
Opportunities before `qualificado` keep the v1.1 rule: `em_andamento`, with Contact values as `inferido`.
Remaining PLAN Open Questions Q2–Q6 are accepted with the planner's planned defaults. Q2 (fail-closed for a label outside the catalog) comes with a pre-deploy check of the published config.
