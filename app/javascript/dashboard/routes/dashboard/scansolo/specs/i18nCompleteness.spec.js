import enMessages from 'dashboard/i18n/locale/en';
import { SCANSOLO_MODULES } from '../scansoloModules';
import { SCANSOLO_PIPELINE_STAGES } from '../pipeline/pipelineConstants';
import { AGENT_CENTER_FIELD_LABELS } from '../agent/agentCenterFields';
import {
  AI_ACTION_LABELS,
  COMMERCIAL_STATUS_LABELS,
  REASON_LABELS,
  STALL_REASON_LABELS,
  SUGGESTED_ACTION_LABELS,
} from '../scansoloLabels';

// Every ScanSolo source file, plus the ScanSolo pieces mounted in native
// Chatwoot screens.
const sources = {
  ...import.meta.glob(['../**/*.{vue,js}', '!../**/specs/**'], {
    query: '?raw',
    import: 'default',
    eager: true,
  }),
  ...import.meta.glob(
    [
      '/app/javascript/dashboard/components-next/conversation/HandoffControlBanner.vue',
      '/app/javascript/dashboard/components-next/sidebar/Sidebar.vue',
    ],
    { query: '?raw', import: 'default', eager: true }
  ),
};

const STATIC_KEY = /['"`](SCANSOLO(?:\.[A-Z0-9_]+)+)['"`]/g;

// Keys built from a known enum, one entry per value.
const HANDOFF_STATES = [
  'ai_active',
  'handoff_requested',
  'awaiting_human',
  'human_active',
  'paused',
  'closed',
];
const KNOWLEDGE_SOURCE_TYPES = ['document', 'faq', 'company_info'];

const enumKeys = [
  ...SCANSOLO_MODULES.flatMap(({ key }) => [
    `SCANSOLO.SIDEBAR.${key.toUpperCase()}`,
    `SCANSOLO.MODULES.${key.toUpperCase()}.TITLE`,
    `SCANSOLO.MODULES.${key.toUpperCase()}.DESCRIPTION`,
  ]),
  ...SCANSOLO_PIPELINE_STAGES.map(
    stage => `SCANSOLO.PIPELINE_BOARD.STAGES.${stage.toUpperCase()}`
  ),
  ...HANDOFF_STATES.map(
    state => `SCANSOLO.HANDOFF_BANNER.STATES.${state.toUpperCase()}`
  ),
  ...KNOWLEDGE_SOURCE_TYPES.map(
    type => `SCANSOLO.KNOWLEDGE_CENTER.SOURCE_TYPES.${type.toUpperCase()}`
  ),
  // Relatórios: API enums rendered through these maps (7 / 10 / 10).
  ...Object.values(COMMERCIAL_STATUS_LABELS),
  ...Object.values(STALL_REASON_LABELS),
  ...Object.values(SUGGESTED_ACTION_LABELS),
];

const resolve = key =>
  key.split('.').reduce((node, part) => node?.[part], enMessages);

describe('ScanSolo i18n completeness', () => {
  const referencedKeys = [
    ...new Set(
      Object.values(sources).flatMap(source =>
        [...source.matchAll(STATIC_KEY)].map(match => match[1])
      )
    ),
  ];

  it('scans the ScanSolo sources', () => {
    expect(referencedKeys.length).toBeGreaterThan(50);
  });

  it('resolves every referenced SCANSOLO key in the real en locale', () => {
    const missing = [...referencedKeys, ...enumKeys].filter(
      key => typeof resolve(key) !== 'string'
    );

    expect(missing).toEqual([]);
  });

  it('covers every Relatórios enum value', () => {
    expect(Object.keys(COMMERCIAL_STATUS_LABELS)).toHaveLength(7);
    expect(Object.keys(STALL_REASON_LABELS)).toHaveLength(10);
    expect(Object.keys(SUGGESTED_ACTION_LABELS)).toEqual(
      Object.keys(STALL_REASON_LABELS)
    );
  });

  it('resolves the Relatórios module, reason and action texts', () => {
    [
      'SCANSOLO.SIDEBAR.REPORTS',
      'SCANSOLO.MODULES.REPORTS.TITLE',
      'SCANSOLO.MODULES.REPORTS.DESCRIPTION',
    ].forEach(key => expect(typeof resolve(key)).toBe('string'));
    expect(resolve(SUGGESTED_ACTION_LABELS.proposta_manual_sem_cadencia)).toBe(
      'Acompanhar com o Artur'
    );
    expect(resolve(SUGGESTED_ACTION_LABELS.outro)).toBe('Revisar manualmente');
  });

  it('resolves the escalação comercial labels naming Artur', () => {
    [
      COMMERCIAL_STATUS_LABELS.escalado_wa,
      REASON_LABELS.commercial_escalated,
      AI_ACTION_LABELS.escalate_to_commercial,
    ].forEach(key => expect(resolve(key)).toMatch(/Artur/));
    expect(resolve(COMMERCIAL_STATUS_LABELS.escalado_wa)).toBe(
      'Encaminhado ao Artur (WhatsApp)'
    );
  });

  it('never shows the internal commercial contact name or a phone number', () => {
    const { REPORTS, COMMERCIAL_STATUS, HANDLED_MANUALLY } =
      enMessages.SCANSOLO;
    const reportTexts = JSON.stringify({
      REPORTS,
      COMMERCIAL_STATUS,
      HANDLED_MANUALLY,
    });

    expect(JSON.stringify(enMessages.SCANSOLO)).not.toMatch(/luciano/i);
    expect(reportTexts).not.toMatch(/\d{4,5}-?\d{4}/);
  });

  it('resolves the Agent Center camelCase field labels', () => {
    [
      'modelProvider',
      'modelSelection',
      'transferCriteria',
      'responseLimits',
      'serviceHours',
      'serviceRules',
      'qualificationPlaybook',
      'requiredQualificationFields',
      'restrictedInformation',
      'forbiddenSubjects',
    ].forEach(field => {
      expect(typeof resolve(AGENT_CENTER_FIELD_LABELS[field])).toBe('string');
    });
  });

  it('never builds an Agent Center key from the field name', () => {
    const agentCenter = sources['../agent/AgentCenter.vue'];

    expect(agentCenter).toBeDefined();
    expect(agentCenter).not.toContain('toUpperCase()');
  });
});
