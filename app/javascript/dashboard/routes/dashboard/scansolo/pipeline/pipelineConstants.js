// Mirrors ScanSolo::PipelineOpportunity's stage enum (RF-06), in the same
// fixed order.
export const SCANSOLO_PIPELINE_STAGES = [
  'novo_lead',
  'em_contato',
  'em_qualificacao',
  'qualificado',
  'proposta_enviada',
  'negociacao',
  'ganho',
  'perdido',
];

// "Novo lead" initial stage, in board order. Stages whose real
// precondition a brand-new lead cannot meet stay listed but disabled with
// their reason; the server (ManualLeadService::INITIAL_STAGES) refuses them
// too. Ganho is not an entry stage.
export const NEW_LEAD_DEFAULT_STAGE = 'novo_lead';
export const NEW_LEAD_STAGE_OPTIONS = [
  { stage: 'novo_lead' },
  { stage: 'em_contato' },
  { stage: 'em_qualificacao' },
  { stage: 'qualificado' },
  { stage: 'proposta_enviada', blockedReason: 'REQUIRES_PROPOSAL' },
  { stage: 'negociacao', blockedReason: 'REQUIRES_PROPOSAL' },
  { stage: 'perdido' },
];

export const MS_PER_DAY = 24 * 60 * 60 * 1000;

// RF-12: fixed, non-account-configurable staleness threshold, mirroring
// ScanSolo::PIPELINE_STALE_THRESHOLD.
export const SCANSOLO_STALE_THRESHOLD_MS = 2 * MS_PER_DAY;

// Mirrors ScanSolo::Pipeline::StageTransitionService::TERMINAL_STAGES.
export const TERMINAL_STAGES = ['ganho', 'perdido'];

// Relatórios RF-04 (Q-01): the single "stalled" rule, mirroring
// ScanSolo::Pipeline::OpportunityQuery.stale? — not terminal and the last
// customer interaction (or the creation, when the customer never wrote) at
// least 48 h before `now`.
export const isStaleOpportunity = (opportunity, now = new Date()) => {
  if (TERMINAL_STAGES.includes(opportunity.stage)) return false;
  const lastActivity =
    opportunity.lastCustomerInteractionAt || opportunity.createdAt;
  return (
    now.getTime() - new Date(lastActivity).getTime() >=
    SCANSOLO_STALE_THRESHOLD_MS
  );
};

// CT-01: mirrors ScanSolo::Commercial::Rules::E164_PHONE_REGEXP.
export const E164_PHONE_PATTERN = /^\+[1-9]\d{1,14}$/;
