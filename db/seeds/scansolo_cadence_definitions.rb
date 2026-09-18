# RF-57: seeds the three initial per-stage cadence schedules. Idempotent
# (find_or_create_by! keyed on stage+version), so it is safe to load more
# than once -- from db/seeds.rb, a rails runner invocation, or a spec. Uses
# a local variable rather than a top-level constant, since this file is
# re-`load`ed (not `require`d) across multiple specs in the same process.
cadence_definitions_seed = [
  { stage: 'novo_lead', version: 1, offsets: [2, 24, 48, 96] },
  { stage: 'em_contato', version: 1, offsets: [24, 48, 72, 96, 120] },
  { stage: 'em_qualificacao', version: 1, offsets: [24, 48, 72, 96, 120, 144, 168] },
  # RF-82: post-proposal follow-up cadence -- enrolled automatically by
  # ScanSolo::Proposal::SuccessHandler once a proposal send is validated as
  # successful. Offsets are a FLEXIBLE default (not RF-57 RIGID), since the
  # SPEC only fixes the pre-proposal cadences.
  { stage: 'proposta_enviada', version: 1, offsets: [24, 72, 168] }
]

cadence_definitions_seed.each do |attrs|
  ScanSolo::CadenceDefinition.find_or_create_by!(stage: attrs[:stage], version: attrs[:version]) do |definition|
    definition.offsets = attrs[:offsets]
    definition.active = true
  end
end
