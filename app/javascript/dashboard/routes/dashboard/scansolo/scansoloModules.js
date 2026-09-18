// Single source of truth for the 6 net-new ScanSolo modules (RF-01). The
// remaining 5 of the 11 required modules (Conversas, Contatos, Equipe,
// Templates, Automação e integrações) are pre-existing native Chatwoot
// navigation entries and are left untouched.
export const SCANSOLO_MODULES = [
  {
    key: 'pipeline',
    path: 'pipeline',
    name: 'scansolo_pipeline_index',
    icon: 'i-lucide-kanban-square',
  },
  {
    key: 'agent',
    path: 'agent',
    name: 'scansolo_agent_index',
    icon: 'i-lucide-bot',
  },
  {
    key: 'knowledge',
    path: 'knowledge',
    name: 'scansolo_knowledge_index',
    icon: 'i-lucide-book-open',
  },
  {
    key: 'followups',
    path: 'followups',
    name: 'scansolo_followups_index',
    icon: 'i-lucide-repeat-2',
  },
  {
    key: 'proposals',
    path: 'proposals',
    name: 'scansolo_proposals_index',
    icon: 'i-lucide-file-text',
  },
  {
    key: 'executions',
    path: 'executions',
    name: 'scansolo_executions_index',
    icon: 'i-lucide-shield-check',
  },
];
