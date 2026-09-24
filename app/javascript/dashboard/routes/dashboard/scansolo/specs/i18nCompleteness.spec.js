import enMessages from 'dashboard/i18n/locale/en';
import { SCANSOLO_MODULES } from '../scansoloModules';
import { SCANSOLO_PIPELINE_STAGES } from '../pipeline/pipelineConstants';
import { AGENT_CENTER_FIELD_LABELS } from '../agent/agentCenterFields';

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
