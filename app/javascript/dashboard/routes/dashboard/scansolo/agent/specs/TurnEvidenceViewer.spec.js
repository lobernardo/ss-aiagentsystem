import { mount, flushPromises } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import ScanSoloAiTurnsAPI from 'dashboard/api/scansoloAiTurns';
import TurnEvidenceViewer from '../TurnEvidenceViewer.vue';

vi.mock('dashboard/api/scansoloAiTurns', () => ({
  default: {
    get: vi.fn(),
    show: vi.fn(),
  },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const turnsFixture = [
  {
    id: 1,
    correlation_id: 'corr-1',
    invocation_status: 'succeeded',
  },
  {
    id: 2,
    correlation_id: 'corr-2',
    invocation_status: 'failed',
  },
];

const turnDetailFixture = {
  id: 1,
  correlation_id: 'corr-1',
  invocation_status: 'succeeded',
  model_provider: 'scansolo_test_mode',
  model_reference: 'scansolo-mock-llm',
  input_tokens: 10,
  output_tokens: 12,
  failure_reason: null,
  guardrail_outcome: { blocked: false, allowed_actions: ['stage_transition'] },
  knowledge_evidence: { results: [], failure_reason: null },
  action_evidence: [{ type: 'stage_transition', target_stage: 'qualificado' }],
};

describe('TurnEvidenceViewer', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    ScanSoloAiTurnsAPI.get.mockResolvedValue({ data: turnsFixture });
    ScanSoloAiTurnsAPI.show.mockResolvedValue({ data: turnDetailFixture });
  });

  it('lists recent turns on mount', async () => {
    const wrapper = mount(TurnEvidenceViewer);
    await flushPromises();

    const rows = wrapper.findAll('[data-testid="turn-row"]');
    expect(rows).toHaveLength(2);
    expect(rows[0].attributes('data-correlation-id')).toBe('corr-1');
  });

  it('selecting a turn shows guardrail outcome, knowledge evidence, and action evidence', async () => {
    const wrapper = mount(TurnEvidenceViewer);
    await flushPromises();

    await wrapper.find('[data-testid="turn-row"]').trigger('click');
    await flushPromises();

    expect(ScanSoloAiTurnsAPI.show).toHaveBeenCalledWith('corr-1');
    expect(wrapper.find('[data-testid="turn-detail"]').exists()).toBe(true);
    expect(
      wrapper.find('[data-testid="detail-guardrail-outcome"]').text()
    ).toContain('allowedActions');
    expect(
      wrapper.find('[data-testid="detail-knowledge-evidence"]').text()
    ).toContain('results');
    expect(
      wrapper.find('[data-testid="detail-action-evidence"]').text()
    ).toContain('stage_transition');
  });

  it('is queryable by correlation id via the search field', async () => {
    const wrapper = mount(TurnEvidenceViewer);
    await flushPromises();

    await wrapper
      .find('[data-testid="field-correlation-id"]')
      .setValue('corr-1');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(ScanSoloAiTurnsAPI.show).toHaveBeenCalledWith('corr-1');
    expect(
      wrapper.find('[data-testid="detail-invocation-status"]').text()
    ).toBe('succeeded');
  });
});
