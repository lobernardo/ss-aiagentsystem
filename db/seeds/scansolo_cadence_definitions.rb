# RF-25: the four per-stage cadence schedules, loaded at deploy time by
# `bundle exec rails scansolo:load_cadence_definitions` (lib/tasks/
# scansolo.rake). Idempotent (find_or_create_by! keyed on stage+version), so
# it is safe to load more than once. Uses a local variable rather than a
# top-level constant, since this file is re-`load`ed (not `require`d)
# across multiple specs in the same process.
cadence_definitions_seed = [
  { stage: 'novo_lead', version: 1, offsets: [2, 24, 48, 96] },
  { stage: 'em_contato', version: 1, offsets: [24, 48, 72, 96, 120] },
  { stage: 'em_qualificacao', version: 1, offsets: [24, 48, 72, 96, 120, 144, 168] },
  # Post-proposal follow-up cadence, enrolled when the opportunity enters
  # proposta_enviada (RF-24).
  { stage: 'proposta_enviada', version: 1, offsets: [24, 72, 168] }
]

cadence_definitions_seed.each do |attrs|
  ScanSolo::CadenceDefinition.find_or_create_by!(stage: attrs[:stage], version: attrs[:version]) do |definition|
    definition.offsets = attrs[:offsets]
    definition.active = true
  end
end
