// UI-03: static camelCase field → i18n key map. Keys are never built from the
// field name, so a camelCase field can't render as a raw key.
export const AGENT_CENTER_FIELD_LABELS = {
  name: 'SCANSOLO.AGENT_CENTER.FIELDS.NAME',
  enabled: 'SCANSOLO.AGENT_CENTER.FIELDS.ENABLED',
  modelProvider: 'SCANSOLO.AGENT_CENTER.FIELDS.MODEL_PROVIDER',
  modelSelection: 'SCANSOLO.AGENT_CENTER.FIELDS.MODEL_SELECTION',
  role: 'SCANSOLO.AGENT_CENTER.FIELDS.ROLE',
  objective: 'SCANSOLO.AGENT_CENTER.FIELDS.OBJECTIVE',
  persona: 'SCANSOLO.AGENT_CENTER.FIELDS.PERSONA',
  tone: 'SCANSOLO.AGENT_CENTER.FIELDS.TONE',
  instructions: 'SCANSOLO.AGENT_CENTER.FIELDS.INSTRUCTIONS',
  serviceRules: 'SCANSOLO.AGENT_CENTER.FIELDS.SERVICE_RULES',
  qualificationPlaybook: 'SCANSOLO.AGENT_CENTER.FIELDS.QUALIFICATION_PLAYBOOK',
  requiredQualificationFields:
    'SCANSOLO.AGENT_CENTER.FIELDS.REQUIRED_QUALIFICATION_FIELDS',
  restrictedInformation: 'SCANSOLO.AGENT_CENTER.FIELDS.RESTRICTED_INFORMATION',
  forbiddenSubjects: 'SCANSOLO.AGENT_CENTER.FIELDS.FORBIDDEN_SUBJECTS',
  transferCriteria: 'SCANSOLO.AGENT_CENTER.FIELDS.TRANSFER_CRITERIA',
  responseLimits: 'SCANSOLO.AGENT_CENTER.FIELDS.RESPONSE_LIMITS',
  serviceHours: 'SCANSOLO.AGENT_CENTER.FIELDS.SERVICE_HOURS',
  requireProposalApproval:
    'SCANSOLO.AGENT_CENTER.FIELDS.REQUIRE_PROPOSAL_APPROVAL',
  allowedInboxIds: 'SCANSOLO.AGENT_CENTER.FIELDS.ALLOWED_INBOX_IDS',
};

export const FIELD_TYPES = {
  CHECKBOX: 'checkbox',
  TEXT: 'text',
  TEXTAREA: 'textarea',
  LIST: 'list',
  INBOXES: 'inboxes',
};

// UI-04: the Agent Center form, in section order.
export const AGENT_CENTER_SECTIONS = [
  {
    key: 'identity',
    title: 'SCANSOLO.AGENT_CENTER.SECTIONS.IDENTITY',
    fields: [
      { name: 'name', type: FIELD_TYPES.TEXT },
      { name: 'enabled', type: FIELD_TYPES.CHECKBOX },
      { name: 'role', type: FIELD_TYPES.TEXT },
      { name: 'persona', type: FIELD_TYPES.TEXT },
    ],
  },
  {
    key: 'model',
    title: 'SCANSOLO.AGENT_CENTER.SECTIONS.MODEL',
    fields: [
      { name: 'modelProvider', type: FIELD_TYPES.TEXT },
      { name: 'modelSelection', type: FIELD_TYPES.TEXT },
    ],
  },
  {
    key: 'behavior',
    title: 'SCANSOLO.AGENT_CENTER.SECTIONS.BEHAVIOR',
    fields: [
      { name: 'objective', type: FIELD_TYPES.TEXT },
      { name: 'tone', type: FIELD_TYPES.TEXT },
      { name: 'instructions', type: FIELD_TYPES.TEXTAREA },
      { name: 'serviceRules', type: FIELD_TYPES.TEXTAREA },
      { name: 'responseLimits', type: FIELD_TYPES.TEXT },
    ],
  },
  {
    key: 'qualification',
    title: 'SCANSOLO.AGENT_CENTER.SECTIONS.QUALIFICATION',
    fields: [
      { name: 'qualificationPlaybook', type: FIELD_TYPES.LIST },
      { name: 'requiredQualificationFields', type: FIELD_TYPES.LIST },
    ],
  },
  {
    key: 'safety',
    title: 'SCANSOLO.AGENT_CENTER.SECTIONS.SAFETY',
    fields: [
      { name: 'restrictedInformation', type: FIELD_TYPES.LIST },
      { name: 'forbiddenSubjects', type: FIELD_TYPES.LIST },
    ],
  },
  {
    key: 'handoff',
    title: 'SCANSOLO.AGENT_CENTER.SECTIONS.HANDOFF',
    fields: [{ name: 'transferCriteria', type: FIELD_TYPES.TEXT }],
  },
  {
    key: 'hours',
    title: 'SCANSOLO.AGENT_CENTER.SECTIONS.HOURS',
    fields: [{ name: 'serviceHours', type: FIELD_TYPES.TEXT }],
  },
  {
    key: 'proposal',
    title: 'SCANSOLO.AGENT_CENTER.SECTIONS.PROPOSAL',
    fields: [{ name: 'requireProposalApproval', type: FIELD_TYPES.CHECKBOX }],
  },
  {
    key: 'channels',
    title: 'SCANSOLO.AGENT_CENTER.SECTIONS.CHANNELS',
    fields: [{ name: 'allowedInboxIds', type: FIELD_TYPES.INBOXES }],
  },
];
