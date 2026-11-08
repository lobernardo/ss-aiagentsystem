# Clarifier questions: scansolo-relatorios-fonte-unica (SPEC v1.0, tier complete)

Mode: analyze. Open markers: M-01, M-02, M-03, M-04 (6 `[NEEDS CLARIFICATION]` occurrences). Ordered by rework risk. The first option in each question is the recommended one.

---

## Q-01 [Marker M-04] ref RF-04, RF-05, RF-06, RF-10, UI-05: What counts as "parado", and what happens when no reason applies?

Gaps found:
1. If `last_customer_interaction_at` is null, the lead is never "parado" (`opportunity_query.rb:5-9`). So a manual lead that never answered can never reach `aguardando_resposta_do_lead` or `cadencia_concluida_sem_resposta`, which are the reasons written for exactly that lead.
2. The RF-10 funnel SQL counts `ganho`/`perdido` as stalled, but RF-05 has no reason for them.
3. RF-10 says every stalled lead appears exactly once in the list with a reason. A stalled lead that matches none of the 8 conditions breaks that rule, and then the funnel's `stalled` count and the list disagree. Examples: `qualificado` + `resposta_recebida`/`proposta_em_aprovacao`, `negociacao` with the AI active, `proposta_enviada_manual` in `qualificado`.

Impact: this decides the funnel SQL in the RF-10 acceptance criterion, whether there are 8 or 9 reasons (RF-06, UI-11, the `i18nCompleteness` enumKeys, the RF-05 spec cases), and whether the Kanban "Inativo" badge changes too (RF-04 says it is "the same rule").

Options:
- **A (recommended):** Reference time = `COALESCE(last_customer_interaction_at, created_at)`. Apply it in one shared place that both the report and the Kanban "Inativo" badge (`OpportunityQuery.stale?` + `pipelineConstants.js`) use, so the rule stays single. `ganho`/`perdido` are never parado (funnel `stalled = 0`). Add a 9th reason, `outro`, with the action "Revisar manualmente", so funnel and list always match.
- **B:** Same as A, but the Kanban badge keeps its current rule (null = not inactive). Accept that the report and the badge diverge for leads that never interacted.
- **C:** Keep the current rule (null = never parado). Exclude `ganho`/`perdido`. Add a 9th reason, `outro`.
- **D:** Use the COALESCE and exclude terminal stages, with no 9th reason: stalled leads with no matching condition are left out of both the list and the funnel's `stalled` count.

---

## Q-02 [Marker M-02 + M-03] ref RF-08, UI-03: How are "respondidos", "tempo até a 1ª resposta" and "qualificados no período" defined?

Context:
- The native `conversations.first_reply_created_at` only records **human** replies (`Message#human_response?`/`valid_first_reply?`, `app/models/message.rb:226,364`). It leaves out AI replies, so it cannot be the source.
- Manual leads created directly in `qualificado` write no `PipelineStageEvent`.

Impact: this decides the 3 SQL references that the confirmed acceptance criterion #1 checks against the database, and the sample used for median/p90.

Options:
- **A (recommended):** Cohort = leads created in the period. `responded` = those whose conversation has ≥ 1 non-private `outgoing` message (AI or human; cadence/template messages included) after the first non-private `incoming`. First-response time = that first `outgoing` − the first `incoming`. Leads with no `incoming` (manual leads that never wrote) are left out of both. `qualified` = distinct opportunities with `PipelineStageEvent.to_stage='qualificado'` and `created_at` in the period, ∪ manual leads created in `qualificado` in the period.
- **B:** "Respondidos" = leads whose **contact replied** (≥ 1 `incoming` after an `outgoing`, which covers manual leads). Time = first `incoming` − first `outgoing`. `qualified` = `PipelineStageEvent` only (manual leads created in `qualificado` are left out).
- **C:** Event cohort: responses that happened in the period, whatever the lead's creation date, with the A definition. `qualified` = `lead_state.qualification_completed` audits in the period (AI qualification only).

---

## Q-03 [Marker M-01] ref RF-13, RF-14, CT-05, CT-06, UI-03: Which week does the snapshot freeze, when does it run, and what happens on a 2nd run?

Gap: a week runs Monday to Sunday (RF-07), but the input asks for a job on "sexta de manhã" (Friday morning).
- A Friday snapshot of the current week leaves out Friday after the run through Sunday. The "past weeks" view would then be permanently incomplete, and 4 weeks would not add up to the month (which is always live).
- The funnel and stalled list in the snapshot reflect `as_of` = the run time, not the end of the week.

Options:
- **A (recommended, departs from the input):** The job runs **Monday 06:00 SP** (`'0 9 * * 1'` UTC) and freezes the **previous full week** (`as_of` ≈ end of the week). A 2nd run for the same `(account, week_start)` **overwrites** it (upsert, last run wins).
- **B (as the input says):** Friday 08:00 SP (`'0 11 * * 5'` UTC) freezes the **current partial week** (Monday 00:00 → run time). Past weeks show that partial week, with the "dados congelados em" notice. A 2nd run in the same week **keeps the first** (insert-only).
- **C:** Friday 08:00 SP freezes the **previous full week** (closed 5 days earlier, funnel/stalled as of Friday). Until Friday, the past week is shown live. A 2nd run overwrites it.

---

## Q-04 [Contradiction] ref RF-16, RF-17, RF-18, Scope Out: Should the manual action (above all the legacy bulk run) enroll the post-proposal cadence?

The input contradicts itself:
- Item 7 says that moving to `proposta_enviada` "enrola a cadência pós-proposta existente" (enrolls the existing post-proposal cadence).
- It also says the bulk run on the 20 legacy requests (13/10–06/11) is "sem envio de mensagem a ninguém" (no message sent to anyone).

The `proposta_enviada` cadence has offsets of 24 h / 72 h / 168 h (`db/seeds/scansolo_cadence_definitions.rb:14`). The way RF-17 is written, all 20 legacy leads would get WhatsApp follow-ups starting 24 h after the bulk action, about proposals Artur sent in person weeks ago. The SPEC's Scope Out also says "Enviar mensagem de qualquer tipo a lead ... como efeito das ações desta feature" (sending any message to a lead as an effect of this feature's actions).

Impact: real messages to real customers, plus a possible change to the "no change to cadence behavior" rule.

Options:
- **A (recommended):** The single action (CT-03) enrolls the cadence, as the input says. The bulk action (CT-04) transitions without an active cadence: it cancels, in the same transaction, the enrollment that `StageEntryEnroller` created, and records a reason in the audit `payload` (e.g. `cadence_skipped: "legacy_bulk"`). RF-17 is rewritten to match.
- **B:** Both enroll the cadence (the SPEC as it is now). Accept follow-ups to the 20 legacy leads.
- **C:** Neither enrolls the cadence. The manual action never schedules follow-ups.
