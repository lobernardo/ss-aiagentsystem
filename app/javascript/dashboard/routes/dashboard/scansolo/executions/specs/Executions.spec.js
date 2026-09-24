import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import ScanSoloExecutionsAPI from 'dashboard/api/scansoloExecutions';
import ScanSoloProposalsAPI from 'dashboard/api/scansoloProposals';
import Executions from '../Executions.vue';

vi.mock('dashboard/api/scansoloExecutions', () => ({
  default: {
    get: vi.fn(),
  },
}));

vi.mock('dashboard/api/scansoloProposals', () => ({
  default: { retry: vi.fn() },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

withFullI18n();
enableAutoUnmount(afterEach);

const CORRELATION_IDS = [
  'corr-dead-letter-1',
  'corr-callback-1',
  'corr-audit-1',
  'corr-handoff-1',
  'corr-turn-1',
];

const executionsFixture = {
  cadence_evidence: [
    {
      id: 11,
      opportunity_id: 3,
      cadence_definition_id: 1,
      status: 'active',
      current_step: 1,
      next_attempt_at: '2026-01-05T12:00:00Z',
      contact_name: 'Maria Silva',
      cadence_stage: 'novo_lead',
      cadence_version: 1,
      attempts: [
        {
          id: 101,
          step: 1,
          cadence_version: 1,
          template_reference: 'scansolo_cadence_novo_lead_v1_step1',
          scheduled_at: '2026-01-05T12:00:00Z',
          sent_at: null,
          result: 'scheduled',
          message_id: null,
          last_block_reason: 'template_paused',
          last_checked_at: '2026-01-05T12:05:00Z',
          external_error: null,
        },
        {
          id: 102,
          step: 2,
          cadence_version: 1,
          template_reference: 'scansolo_cadence_novo_lead_v1_step2',
          scheduled_at: '2026-01-06T12:00:00Z',
          sent_at: null,
          result: 'failed',
          message_id: 555,
          last_block_reason: null,
          last_checked_at: null,
          external_error: '(#131047) Re-engagement message',
        },
      ],
    },
  ],
  template_availability: [
    {
      stage: 'novo_lead',
      step: 1,
      template_name: 'scansolo_novo_lead_1',
      language: 'pt_BR',
      params: [],
      mapped: true,
      availability: 'blocked',
      block_reason: 'template_paused',
      meta_status: 'PAUSED',
      last_synced_at: null,
    },
  ],
  make_errors: {
    dead_letters: [
      {
        id: 21,
        action: 'proposal.generate',
        correlation_id: 'corr-dead-letter-1',
        idempotency_key: 'idem-1',
        retry_count: 4,
        status: 'failed',
        proposal_id: 9,
        proposal_version_id: 90,
        created_at: '2026-01-05T12:00:00Z',
      },
    ],
    callback_errors: [
      {
        id: 31,
        action: 'proposal.generate',
        correlation_id: 'corr-callback-1',
        signature_valid: true,
        applied: false,
        rejection_reason: 'schema_invalid',
        created_at: '2026-01-05T12:05:00Z',
      },
    ],
  },
  handoff_events: [
    {
      id: 51,
      conversation_id: 7,
      event_type: 'handoff.takeover',
      trigger: 'implicit',
      actor_type: 'User',
      actor_id: 5,
      correlation_id: 'corr-handoff-1',
      created_at: '2026-01-05T12:07:00Z',
    },
    {
      id: 52,
      conversation_id: 7,
      event_type: 'handoff.takeover',
      trigger: 'explicit',
      actor_type: 'User',
      actor_id: 5,
      correlation_id: 'corr-handoff-2',
      created_at: '2026-01-05T12:08:00Z',
    },
  ],
  recent_errors: [
    {
      kind: 'ai_turn',
      id: 61,
      reason: 'stale_pending',
      correlation_id: 'corr-turn-1',
      occurred_at: '2026-01-05T12:09:00Z',
    },
  ],
  audit_events: [
    {
      id: 41,
      event_type: 'agent_action.private_note.create',
      subject_type: 'ScanSolo::AgentActionExecution',
      subject_id: 7,
      actor_type: 'User',
      actor_id: 5,
      correlation_id: 'corr-audit-1',
      payload: {},
      created_at: '2026-01-05T12:10:00Z',
    },
  ],
};

const mountExecutions = ({ role = 'administrator' } = {}) =>
  mount(Executions, {
    global: {
      plugins: [
        createStore({
          getters: {
            getCurrentRole: () => role,
            getCurrentUser: () => ({ id: 1 }),
          },
        }),
      ],
    },
  });

const technicalText = row =>
  row.find('[data-testid="technical-details"]').text();

describe('Executions', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    ScanSoloExecutionsAPI.get.mockResolvedValue({ data: executionsFixture });
  });

  it('renders cadence evidence with attempt template references (RF-62)', async () => {
    const wrapper = mountExecutions();
    await flushPromises();

    const row = wrapper.find(
      '[data-testid="cadence-evidence-row"][data-enrollment-id="11"]'
    );
    expect(row.exists()).toBe(true);
    expect(
      row.find('[data-testid="cadence-evidence-attempt-template"]').text()
    ).toContain('scansolo_cadence_novo_lead_v1_step1');
    expect(row.find('[data-testid="cadence-evidence-status"]').text()).toBe(
      'Ativa'
    );
  });

  it('renders attempt result, block reason and delivery evidence (RF-61)', async () => {
    const wrapper = mountExecutions();
    await flushPromises();

    const deferred = wrapper.find('[data-attempt-id="101"]');
    expect(
      deferred.find('[data-testid="cadence-evidence-attempt-result"]').text()
    ).toContain('Agendada');
    expect(
      deferred
        .find('[data-testid="cadence-evidence-attempt-block-reason"]')
        .text()
    ).toContain('Modelo pausado pela Meta');

    const failed = wrapper.find('[data-attempt-id="102"]');
    expect(
      failed.find('[data-testid="cadence-evidence-attempt-delivery"]').text()
    ).toContain('Mensagem registrada na conversa');
    expect(
      failed
        .find('[data-testid="cadence-evidence-attempt-external-error"]')
        .text()
    ).toContain('Re-engagement message');
  });

  it('renders template availability rows', async () => {
    const wrapper = mountExecutions();
    await flushPromises();

    const row = wrapper.find('[data-testid="template-availability-row"]');
    expect(row.text()).toContain('scansolo_novo_lead_1');
    expect(row.find('[data-testid="template-availability-state"]').text()).toBe(
      'Bloqueado'
    );
    expect(row.text()).toContain('Modelo pausado pela Meta');
  });

  it('renders a rejected Make callback with its reason (UI-09 AC)', async () => {
    const wrapper = mountExecutions();
    await flushPromises();

    const row = wrapper.find(
      '[data-testid="make-callback-error-row"][data-callback-id="31"]'
    );
    expect(row.exists()).toBe(true);
    expect(row.find('[data-testid="make-callback-error-reason"]').text()).toBe(
      'Formato fora do contrato'
    );
    expect(technicalText(row)).toContain('corr-callback-1');
  });

  it('renders Make dead-letter requests', async () => {
    const wrapper = mountExecutions();
    await flushPromises();

    const row = wrapper.find(
      '[data-testid="make-dead-letter-row"][data-request-id="21"]'
    );
    expect(row.exists()).toBe(true);
    expect(row.text()).toContain('Gerar proposta');
    expect(technicalText(row)).toContain('corr-dead-letter-1');
  });

  it('renders explicit and implicit handoff events', async () => {
    const wrapper = mountExecutions();
    await flushPromises();

    const triggers = wrapper
      .findAll('[data-testid="handoff-event-trigger"]')
      .map(node => node.text());
    expect(triggers).toEqual(['Resposta humana', 'Manual']);
    expect(wrapper.find('[data-testid="handoff-event-type"]').text()).toBe(
      'Humano assumiu'
    );
  });

  it('renders recent errors', async () => {
    const wrapper = mountExecutions();
    await flushPromises();

    const row = wrapper.find('[data-testid="recent-error-row"]');
    expect(row.find('[data-testid="recent-error-kind"]').text()).toBe(
      'Turno de IA'
    );
    expect(row.find('[data-testid="recent-error-reason"]').text()).toBe(
      'Turno expirou sem resposta'
    );
  });

  it('renders action audit records', async () => {
    const wrapper = mountExecutions();
    await flushPromises();

    const row = wrapper.find(
      '[data-testid="audit-event-row"][data-event-id="41"]'
    );
    expect(row.exists()).toBe(true);
    expect(row.find('[data-testid="audit-event-type"]').text()).toContain(
      'agent_action.private_note.create'
    );
  });

  it('reprocesses a dead letter through CT-04 retry only after confirmation', async () => {
    ScanSoloProposalsAPI.retry.mockResolvedValue({ data: {} });
    const wrapper = mountExecutions();
    await flushPromises();

    await wrapper.find('[data-testid="reprocess-button"]').trigger('click');
    expect(ScanSoloProposalsAPI.retry).not.toHaveBeenCalled();
    expect(
      wrapper.find('[data-testid="confirm-dialog-message"]').text()
    ).toContain('Reprocessar cria uma nova requisição');

    await wrapper
      .find('[data-testid="confirm-dialog-confirm"]')
      .trigger('click');
    await flushPromises();

    expect(ScanSoloProposalsAPI.retry).toHaveBeenCalledWith(9, 90, true);
    expect(ScanSoloExecutionsAPI.get).toHaveBeenCalledTimes(2);
    expect(useAlert).toHaveBeenCalledWith('Reprocessamento solicitado.');
  });

  it('hides reprocess and every correlation id from agents', async () => {
    const wrapper = mountExecutions({ role: 'agent' });
    await flushPromises();

    expect(wrapper.find('[data-testid="reprocess-button"]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-testid="technical-details"]').exists()).toBe(
      false
    );
    const html = wrapper.html();
    CORRELATION_IDS.forEach(id => expect(html).not.toContain(id));
    expect(html).not.toMatch(/\d{4}-\d{2}-\d{2}T/);
  });

  it('shows empty states when there is no data', async () => {
    ScanSoloExecutionsAPI.get.mockResolvedValue({
      data: { cadence_evidence: [], make_errors: {}, audit_events: [] },
    });

    const wrapper = mountExecutions();
    await flushPromises();

    [
      'cadence-evidence-empty-state',
      'make-errors-empty-state',
      'handoff-events-empty-state',
      'recent-errors-empty-state',
      'audit-events-empty-state',
    ].forEach(testId => {
      expect(wrapper.find(`[data-testid="${testId}"]`).exists()).toBe(true);
    });
  });

  it('renders the loading and error states (UI-09)', async () => {
    ScanSoloExecutionsAPI.get.mockReturnValueOnce(new Promise(() => {}));
    const loading = mountExecutions();
    await flushPromises();
    expect(loading.find('[data-testid="list-state-loading"]').exists()).toBe(
      true
    );

    ScanSoloExecutionsAPI.get.mockRejectedValueOnce(new Error('boom'));
    const failed = mountExecutions();
    await flushPromises();
    expect(failed.find('[data-testid="list-state-error"]').exists()).toBe(true);
  });
});
