import { mount, flushPromises } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import ScanSoloExecutionsAPI from 'dashboard/api/scansoloExecutions';
import Executions from '../Executions.vue';

vi.mock('dashboard/api/scansoloExecutions', () => ({
  default: {
    get: vi.fn(),
  },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

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
        },
      ],
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
        rejection_reason: 'processing_error',
        created_at: '2026-01-05T12:05:00Z',
      },
    ],
  },
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

describe('Executions', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    ScanSoloExecutionsAPI.get.mockResolvedValue({ data: executionsFixture });
  });

  it('renders cadence evidence with attempt template references (RF-62)', async () => {
    const wrapper = mount(Executions);
    await flushPromises();

    const row = wrapper.find(
      '[data-testid="cadence-evidence-row"][data-enrollment-id="11"]'
    );
    expect(row.exists()).toBe(true);
    expect(
      row.find('[data-testid="cadence-evidence-attempt-template"]').text()
    ).toContain('scansolo_cadence_novo_lead_v1_step1');
  });

  it('renders a simulated failed Make callback fixture in the error view (UI-09 AC)', async () => {
    const wrapper = mount(Executions);
    await flushPromises();

    const row = wrapper.find(
      '[data-testid="make-callback-error-row"][data-callback-id="31"]'
    );
    expect(row.exists()).toBe(true);
    expect(
      row.find('[data-testid="make-callback-error-correlation-id"]').text()
    ).toBe('corr-callback-1');
    expect(row.find('[data-testid="make-callback-error-reason"]').text()).toBe(
      'processing_error'
    );
  });

  it('renders Make dead-letter requests', async () => {
    const wrapper = mount(Executions);
    await flushPromises();

    const row = wrapper.find(
      '[data-testid="make-dead-letter-row"][data-request-id="21"]'
    );
    expect(row.exists()).toBe(true);
    expect(
      row.find('[data-testid="make-dead-letter-correlation-id"]').text()
    ).toBe('corr-dead-letter-1');
  });

  it('renders action audit records', async () => {
    const wrapper = mount(Executions);
    await flushPromises();

    const row = wrapper.find(
      '[data-testid="audit-event-row"][data-event-id="41"]'
    );
    expect(row.exists()).toBe(true);
    expect(row.find('[data-testid="audit-event-type"]').text()).toContain(
      'agent_action.private_note.create'
    );
  });

  it('shows empty states when there is no data', async () => {
    ScanSoloExecutionsAPI.get.mockResolvedValue({
      data: { cadence_evidence: [], make_errors: {}, audit_events: [] },
    });

    const wrapper = mount(Executions);
    await flushPromises();

    expect(
      wrapper.find('[data-testid="cadence-evidence-empty-state"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="make-errors-empty-state"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="audit-events-empty-state"]').exists()
    ).toBe(true);
  });
});
