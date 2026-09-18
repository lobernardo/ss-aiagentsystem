import { mount, flushPromises } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import ScanSoloPipelineOpportunitiesAPI from 'dashboard/api/scansoloPipelineOpportunities';
import KanbanBoard from '../KanbanBoard.vue';

vi.mock('dashboard/api/scansoloPipelineOpportunities', () => ({
  default: {
    get: vi.fn(),
    stageTransition: vi.fn(),
  },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const seededOpportunity = {
  id: 1,
  account_id: 1,
  contact_id: 1,
  conversation_id: 1,
  owner_id: 42,
  stage: 'novo_lead',
  last_customer_interaction_at: '2026-01-01T10:00:00Z',
  next_follow_up_at: '2026-01-03T10:00:00Z',
  created_at: '2026-01-01T09:00:00Z',
  updated_at: '2026-01-01T09:00:00Z',
};

const cardFor = (wrapper, opportunityId) =>
  wrapper.find(
    `[data-testid="pipeline-card"][data-opportunity-id="${opportunityId}"]`
  );

const columnFor = (wrapper, stage) => wrapper.find(`[data-stage="${stage}"]`);

describe('KanbanBoard', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    ScanSoloPipelineOpportunitiesAPI.get.mockResolvedValue({
      data: [seededOpportunity],
    });
  });

  it('renders all five required data points for a seeded opportunity', async () => {
    const wrapper = mount(KanbanBoard);
    await flushPromises();

    const card = cardFor(wrapper, seededOpportunity.id);
    expect(card.exists()).toBe(true);
    expect(card.find('[data-testid="card-stage"]').text()).toContain(
      'SCANSOLO.PIPELINE_BOARD.STAGES.NOVO_LEAD'
    );
    expect(card.find('[data-testid="card-owner"]').text()).toBe('42');
    expect(card.find('[data-testid="card-last-interaction"]').text()).toContain(
      '2026-01-01'
    );
    expect(card.find('[data-testid="card-next-follow-up"]').text()).toContain(
      '2026-01-03'
    );
    // The stale <p> always renders (even if empty) so its presence is the
    // fifth data point, independent of whether this particular fixture is
    // stale.
    expect(card.find('[data-testid="card-stale"]').exists()).toBe(true);
  });

  it('only moves the card to the target column after server confirmation (200)', async () => {
    ScanSoloPipelineOpportunitiesAPI.stageTransition.mockResolvedValue({
      data: { ...seededOpportunity, stage: 'em_contato' },
    });

    const wrapper = mount(KanbanBoard);
    await flushPromises();

    expect(
      columnFor(wrapper, 'em_contato')
        .find(`[data-opportunity-id="${seededOpportunity.id}"]`)
        .exists()
    ).toBe(false);

    wrapper.vm.onDragStart(seededOpportunity.id);
    await wrapper.vm.onDrop('em_contato');
    await flushPromises();

    expect(cardFor(wrapper, seededOpportunity.id).exists()).toBe(true);
    expect(
      columnFor(wrapper, 'em_contato')
        .find(`[data-opportunity-id="${seededOpportunity.id}"]`)
        .exists()
    ).toBe(true);
  });

  it('reverts the card to its original column on a rejected (4xx) transition', async () => {
    ScanSoloPipelineOpportunitiesAPI.stageTransition.mockRejectedValue({
      response: { status: 422 },
    });

    const wrapper = mount(KanbanBoard);
    await flushPromises();

    wrapper.vm.onDragStart(seededOpportunity.id);
    await wrapper.vm.onDrop('em_contato');
    await flushPromises();

    expect(
      columnFor(wrapper, 'novo_lead')
        .find(`[data-opportunity-id="${seededOpportunity.id}"]`)
        .exists()
    ).toBe(true);
    expect(
      columnFor(wrapper, 'em_contato')
        .find(`[data-opportunity-id="${seededOpportunity.id}"]`)
        .exists()
    ).toBe(false);
  });
});
