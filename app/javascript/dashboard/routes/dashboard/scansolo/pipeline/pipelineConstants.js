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

// RF-12: fixed, non-account-configurable staleness threshold, mirroring
// ScanSolo::PIPELINE_STALE_THRESHOLD.
export const SCANSOLO_STALE_THRESHOLD_MS = 48 * 60 * 60 * 1000;
