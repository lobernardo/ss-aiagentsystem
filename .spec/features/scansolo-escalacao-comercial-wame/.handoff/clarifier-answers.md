# Clarifier answers (developer, 2026-11-09)

All four questions answered with the recommended option A.

## Q-01 (M1+M2+M7; RF-09, RF-11, RF-17) — A
- Storage: two nullable additive columns on `scan_solo_pipeline_opportunities`: `escalated_to_commercial_at` and `escalation_reason`. Each new escalation overwrites both; history = one `commercial.escalated` audit event per escalation.
- Lifetime: escalated state lasts until the opportunity reaches `ganho` or `perdido`.
- Cadence: held by a new defer reason in `Cadence::AttemptPrecheck` (single entry point; also covers enrollments created after escalation; nothing to resume). Do NOT reuse the `handoff` pausing trigger.
- `CommercialStatus`: proposal states keep precedence (`proposta_enviada_manual`, `proposta_enviada`, `proposta_em_aprovacao` still win); `escalado_wa` replaces `nao_encaminhado`, `aguardando_artur`, `resposta_recebida`. `CommercialStatus.call` gains the escalation input.

## Q-02 (M3+M4; RF-14, RF-15) — A
- Doubt/negotiation in `qualificado`: stage stays `qualificado`; lead is escalated; the commercial notice e-mail (`negotiation.requested` path) is still sent.
- E-mail cited in replies: the published `quote_recipient_email` (default `comercial@scansolo.com.br`), not a hardcoded literal.

## Q-03 (M5; RF-01, RF-19, CT-01) — A
- Publishing a config with `enabled = true` requires `commercial_whatsapp_number` (422 at publish).
- A published snapshot without the number: `escalate_to_commercial` action and escalation prompt rules are not offered; negotiation sends the existing standard reply (no failure).

## Q-04 (M6; RF-20) — A
- Writing a knowledge source or FAQ containing /luciano/i returns 422 at the knowledge controller boundary; RF-08 output block remains.
- Existing production KB rows: one-off manual check, outside code (note as operational prerequisite).

## Specifier assumptions — accepted as stated
- `human_handoff` removed from model-offered actions (side effect: no internal note/assignment on `pedido_humano`/negotiation; visibility via audit, board status and the notice e-mail).
- One regeneration on unpublished `wa.me`/phone via existing `REGENERABLE_VIOLATIONS`.
- `DECISOES.md` is an external prerequisite.
