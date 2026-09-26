# Developer answers — clarifier resolve (all recommended options chosen)

- Q-01 (RF-15/CT-05): A1 + B1. Consider all 10 canonical keys (empresa, endereco_obra, cidade_uf, tipo_intervencao, area, profundidade, prazo_desejado, email, nome, telefone) regardless of required list; send only keys with a value; omit unsatisfied. Exclude integracao_seguranca and RF-05 unmapped keys. CT-05 description: "fixed canonical key set, present-only".
- Q-02 (RF-21): A1 + B1. Writes go to the canonical key. Read precedence: exact canonical key > exact published config label > other alias matches in alias-table order > lexicographic. No rewrite of existing keys.
- Q-03 (RF-09/RF-11): B. Accept keys resolving to published required fields PLUS the 3 native keys (nome, email, telefone), under RF-10 no-overwrite rule. Stage transition (RF-12) still driven only by required list.
- Q-04 (RF-10): A. Validate native values before the single update; drop only invalid native attributes, report them in result as not applied with reason; save the rest in exactly one update.
- Q-05 (RF-04): A. Frozen code constant, not editable. No migration; CT-01 unchanged. Remove "decide in PLAN" wording.
- Q-06 (RF-19): A. Out of scope — drop RF-19 (move to cycle 2 with Kanban/UX). No opportunity-detail change this cycle.
- Q-07: A + (i). Integration specs assert on MockLlmProvider.last_payload (3 fixed rules present; missing_fields excludes Nome when contact.name exists; history holds the technical question) and on what the fixture qualification_field action saved. "Return after handoff" = agent does not re-ask already satisfied fields, asserted via last_payload missing_fields. Add matching AC to RF-08 or RF-17.
- Q-08: (1) yes — Metadata Tier: complete. (2) A — add "-" to the separator set in RF-03.
