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

export const MS_PER_DAY = 24 * 60 * 60 * 1000;

// RF-12: fixed, non-account-configurable staleness threshold, mirroring
// ScanSolo::PIPELINE_STALE_THRESHOLD.
export const SCANSOLO_STALE_THRESHOLD_MS = 2 * MS_PER_DAY;

// CT-01: mirrors the controller's E164_PHONE_REGEXP.
export const E164_PHONE_PATTERN = /^\+[1-9]\d{1,14}$/;
