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
  allowedInboxIds: 'SCANSOLO.AGENT_CENTER.FIELDS.ALLOWED_INBOX_IDS',
  optOutKeywords: 'SCANSOLO.AGENT_CENTER.FIELDS.OPT_OUT_KEYWORDS',
  quoteInboxId: 'SCANSOLO.AGENT_CENTER.FIELDS.QUOTE_INBOX_ID',
  commercialUserId: 'SCANSOLO.AGENT_CENTER.FIELDS.COMMERCIAL_USER_ID',
  quoteRecipientEmail: 'SCANSOLO.AGENT_CENTER.FIELDS.QUOTE_RECIPIENT_EMAIL',
};

export const FIELD_TYPES = {
  CHECKBOX: 'checkbox',
  TEXT: 'text',
  TEXTAREA: 'textarea',
  LIST: 'list',
  INBOXES: 'inboxes',
  SELECT: 'select',
  KEYWORDS: 'keywords',
  EMAIL: 'email',
};

// UI-08 / RF-54: sources of the form selects.
export const SELECT_OPTIONS = {
  PROVIDERS: 'providers',
  MODELS: 'models',
  EMAIL_INBOXES: 'emailInboxes',
  AGENTS: 'agents',
};

export const SELECT_PLACEHOLDERS = {
  [SELECT_OPTIONS.PROVIDERS]:
    'SCANSOLO.AGENT_CENTER.MODEL_PROVIDER_PLACEHOLDER',
  [SELECT_OPTIONS.MODELS]: 'SCANSOLO.AGENT_CENTER.MODEL_SELECTION_PLACEHOLDER',
  [SELECT_OPTIONS.EMAIL_INBOXES]:
    'SCANSOLO.AGENT_CENTER.QUOTE_INBOX_PLACEHOLDER',
  [SELECT_OPTIONS.AGENTS]: 'SCANSOLO.AGENT_CENTER.COMMERCIAL_USER_PLACEHOLDER',
};

// Mirrors the scan_solo_ai_agent_configs.opt_out_keywords column default.
export const DEFAULT_OPT_OUT_KEYWORDS = ['PARAR', 'SAIR', 'STOP'];

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
      {
        name: 'modelProvider',
        type: FIELD_TYPES.SELECT,
        options: SELECT_OPTIONS.PROVIDERS,
      },
      {
        name: 'modelSelection',
        type: FIELD_TYPES.SELECT,
        options: SELECT_OPTIONS.MODELS,
      },
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
      { name: 'optOutKeywords', type: FIELD_TYPES.KEYWORDS },
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
  // RF-54: the approval toggle left the screen (RF-55 Etapa 1, UI-06); the
  // commercial routing fields take its place. `nullable` selects may be
  // left empty.
  {
    key: 'commercial',
    title: 'SCANSOLO.AGENT_CENTER.SECTIONS.COMMERCIAL',
    fields: [
      {
        name: 'quoteInboxId',
        type: FIELD_TYPES.SELECT,
        options: SELECT_OPTIONS.EMAIL_INBOXES,
        nullable: true,
      },
      {
        name: 'commercialUserId',
        type: FIELD_TYPES.SELECT,
        options: SELECT_OPTIONS.AGENTS,
        nullable: true,
      },
      { name: 'quoteRecipientEmail', type: FIELD_TYPES.EMAIL },
    ],
  },
  {
    key: 'channels',
    title: 'SCANSOLO.AGENT_CENTER.SECTIONS.CHANNELS',
    fields: [{ name: 'allowedInboxIds', type: FIELD_TYPES.INBOXES }],
  },
];
