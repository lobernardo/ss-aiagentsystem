import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import ScanSoloAiTurnsAPI from 'dashboard/api/scansoloAiTurns';
import TurnEvidenceViewer from '../TurnEvidenceViewer.vue';

vi.mock('dashboard/api/scansoloAiTurns', () => ({
  default: {
    get: vi.fn(),
    show: vi.fn(),
  },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

withFullI18n();
enableAutoUnmount(afterEach);

const ISO_PATTERN = /\d{4}-\d{2}-\d{2}T/;
const CORRELATION_ID = '0d9f8e7c-6b5a-4c3d-8e2f-1a0b9c8d7e6f';

const turnsFixture = [
  {
    id: 1,
    correlation_id: CORRELATION_ID,
    invocation_status: 'succeeded',
    created_at: '2026-01-05T12:00:00Z',
  },
  {
    id: 2,
    correlation_id: 'corr-2',
    invocation_status: 'failed',
    created_at: '2026-01-05T12:01:00Z',
  },
];

const turnDetailFixture = {
  id: 1,
  correlation_id: CORRELATION_ID,
  conversation_id: 3,
  message_id: 4,
  invocation_status: 'succeeded',
  model_provider: 'openai',
  model_reference: 'gpt-4.1-mini',
  input_tokens: 10,
  output_tokens: 12,
  latency_ms: 842,
  response_delivery_status: 'delivered',
  failure_reason: null,
  guardrail_outcome: { blocked: false, allowed_actions: ['stage_transition'] },
  knowledge_evidence: [
    {
      source_id: 7,
      source_title: 'Política de garantia',
      chunk_id: 70,
      similarity_score: 0.912,
    },
    {
      source_id: 8,
      source_title: 'Horário de atendimento',
      chunk_id: 80,
      similarity_score: 0.75,
    },
  ],
  action_evidence: [
    { action_id: 'stage_transition', index: 0, execution_id: 9, result: {} },
  ],
  context_snapshot: { history: ['Oi'] },
  created_at: '2026-01-05T12:00:00Z',
};

const mountViewer = ({ role = 'administrator' } = {}) =>
  mount(TurnEvidenceViewer, {
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

const openFirstTurn = async wrapper => {
  await wrapper.find('[data-testid="turn-row"]').trigger('click');
  await flushPromises();
};

describe('TurnEvidenceViewer', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    ScanSoloAiTurnsAPI.get.mockResolvedValue({ data: turnsFixture });
    ScanSoloAiTurnsAPI.show.mockResolvedValue({ data: turnDetailFixture });
  });

  it('lists recent turns on mount with pt-BR status labels', async () => {
    const wrapper = mountViewer();
    await flushPromises();

    const rows = wrapper.findAll('[data-testid="turn-row"]');
    expect(rows).toHaveLength(2);
    expect(rows[0].find('[data-testid="turn-row-status"]').text()).toBe(
      'Concluído'
    );
    expect(rows[1].find('[data-testid="turn-row-status"]').text()).toBe(
      'Falhou'
    );
  });

  it('selecting a turn shows knowledge evidence titles and scores, latency, delivery and actions', async () => {
    const wrapper = mountViewer();
    await flushPromises();
    await openFirstTurn(wrapper);

    expect(ScanSoloAiTurnsAPI.show).toHaveBeenCalledWith(CORRELATION_ID);
    expect(wrapper.find('[data-testid="turn-detail"]').exists()).toBe(true);
    const evidence = wrapper
      .findAll('[data-testid="knowledge-evidence-item"]')
      .map(item => item.text());
    expect(evidence).toEqual([
      'Política de garantia · Similaridade: 0.91',
      'Horário de atendimento · Similaridade: 0.75',
    ]);
    expect(wrapper.find('[data-testid="detail-latency"]').text()).toBe(
      '842 ms'
    );
    expect(wrapper.find('[data-testid="detail-delivery-status"]').text()).toBe(
      'Entregue'
    );
    expect(
      wrapper.find('[data-testid="detail-action-evidence"]').text()
    ).toContain('Mudança de estágio');
  });

  it('shows the empty knowledge evidence message and the failure reason', async () => {
    ScanSoloAiTurnsAPI.show.mockResolvedValue({
      data: {
        ...turnDetailFixture,
        invocation_status: 'failed',
        failure_reason: 'stale_pending',
        knowledge_evidence: [],
        response_delivery_status: null,
        latency_ms: null,
      },
    });
    const wrapper = mountViewer();
    await flushPromises();
    await openFirstTurn(wrapper);

    expect(
      wrapper.find('[data-testid="detail-knowledge-evidence-empty"]').exists()
    ).toBe(true);
    expect(wrapper.find('[data-testid="detail-failure-reason"]').text()).toBe(
      'Turno expirou sem resposta'
    );
    expect(wrapper.find('[data-testid="detail-delivery-status"]').text()).toBe(
      'Nenhuma resposta enviada'
    );
  });

  it('is queryable by correlation id via the search field (administrators)', async () => {
    const wrapper = mountViewer();
    await flushPromises();

    await wrapper
      .find('[data-testid="field-correlation-id"]')
      .setValue(CORRELATION_ID);
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(ScanSoloAiTurnsAPI.show).toHaveBeenCalledWith(CORRELATION_ID);
    expect(
      wrapper.find('[data-testid="detail-invocation-status"]').text()
    ).toBe('Concluído');
  });

  it('shows agents 0 correlation ids, ISO strings or raw JSON', async () => {
    const wrapper = mountViewer({ role: 'agent' });
    await flushPromises();
    await openFirstTurn(wrapper);

    const html = wrapper.html();
    expect(html).not.toContain(CORRELATION_ID);
    expect(html).not.toMatch(ISO_PATTERN);
    expect(html).not.toContain('allowedActions');
    expect(wrapper.find('[data-testid="field-correlation-id"]').exists()).toBe(
      false
    );
  });

  it('shows administrators the correlation id and raw JSON inside the collapsed block', async () => {
    const wrapper = mountViewer();
    await flushPromises();
    await openFirstTurn(wrapper);

    const details = wrapper.find('[data-testid="technical-details"]');
    expect(details.attributes('open')).toBeUndefined();
    expect(details.text()).toContain(CORRELATION_ID);
    expect(details.text()).toMatch(ISO_PATTERN);
    expect(details.text()).toContain('allowedActions');
  });

  it('renders the loading and error states (UI-09)', async () => {
    ScanSoloAiTurnsAPI.get.mockReturnValueOnce(new Promise(() => {}));
    const loading = mountViewer();
    await flushPromises();
    expect(loading.find('[data-testid="list-state-loading"]').exists()).toBe(
      true
    );

    ScanSoloAiTurnsAPI.get.mockRejectedValueOnce(new Error('boom'));
    const failed = mountViewer();
    await flushPromises();
    expect(failed.find('[data-testid="list-state-error"]').exists()).toBe(true);
  });
});
