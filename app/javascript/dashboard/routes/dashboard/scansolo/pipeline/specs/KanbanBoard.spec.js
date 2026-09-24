import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import ScanSoloPipelineOpportunitiesAPI from 'dashboard/api/scansoloPipelineOpportunities';
import KanbanBoard from '../KanbanBoard.vue';

vi.mock('dashboard/api/scansoloPipelineOpportunities', () => ({
  default: {
    get: vi.fn(),
    stageTransition: vi.fn(),
  },
}));

withFullI18n();
enableAutoUnmount(afterEach);

const ISO_PATTERN = /\d{4}-\d{2}-\d{2}T/;

const seededOpportunity = {
  id: 1,
  account_id: 1,
  contact_id: 1,
  contact_name: 'Maria Silva',
  conversation_id: 1,
  owner_id: 42,
  stage: 'novo_lead',
  last_customer_interaction_at: '2026-01-01T10:00:00Z',
  next_follow_up_at: '2026-01-03T10:00:00Z',
  created_at: '2026-01-01T09:00:00Z',
  updated_at: '2026-01-01T09:00:00Z',
};

const getAgentsAction = vi.fn();

const mountBoard = ({ role = 'administrator' } = {}) =>
  mount(KanbanBoard, {
    global: {
      plugins: [
        createStore({
          getters: {
            getCurrentRole: () => role,
            getCurrentUser: () => ({ id: 1 }),
            'agents/getAgents': () => [{ id: 42, name: 'Carla Vendas' }],
          },
          actions: { 'agents/get': getAgentsAction },
        }),
      ],
    },
  });

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
    const wrapper = mountBoard();
    await flushPromises();

    const card = cardFor(wrapper, seededOpportunity.id);
    expect(card.exists()).toBe(true);
    expect(card.find('[data-testid="card-stage"]').text()).toBe('Novo Lead');
    expect(card.find('[data-testid="card-owner"]').text()).toBe(
      'Responsável: Carla Vendas'
    );
    expect(
      card.find('[data-testid="card-last-interaction"]').attributes('title')
    ).toBe('01/01/2026 10:00');
    expect(
      card.find('[data-testid="card-next-follow-up"]').attributes('title')
    ).toBe('03/01/2026 10:00');
    // The stale <p> always renders (even if empty) so its presence is the
    // fifth data point, independent of whether this particular fixture is
    // stale.
    expect(card.find('[data-testid="card-stale"]').exists()).toBe(true);
    expect(getAgentsAction).toHaveBeenCalled();
  });

  it('shows agents 0 technical ids or ISO strings', async () => {
    const wrapper = mountBoard({ role: 'agent' });
    await flushPromises();

    expect(wrapper.find('[data-testid="technical-details"]').exists()).toBe(
      false
    );
    expect(wrapper.html()).not.toMatch(ISO_PATTERN);
    expect(
      cardFor(wrapper, seededOpportunity.id)
        .find('[data-testid="card-owner"]')
        .text()
    ).not.toContain('42');
  });

  it('shows administrators the ids and raw timestamp inside the collapsed block', async () => {
    const wrapper = mountBoard();
    await flushPromises();

    const details = cardFor(wrapper, seededOpportunity.id).find(
      '[data-testid="technical-details"]'
    );
    expect(details.attributes('open')).toBeUndefined();
    expect(details.text()).toContain('42');
    expect(details.text()).toMatch(ISO_PATTERN);
  });

  it('only moves the card to the target column after server confirmation (200)', async () => {
    ScanSoloPipelineOpportunitiesAPI.stageTransition.mockResolvedValue({
      data: { ...seededOpportunity, stage: 'em_contato' },
    });

    const wrapper = mountBoard();
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

    const wrapper = mountBoard();
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

  it('renders the loading, empty and error states (UI-09)', async () => {
    ScanSoloPipelineOpportunitiesAPI.get.mockReturnValueOnce(
      new Promise(() => {})
    );
    const loading = mountBoard();
    await flushPromises();
    expect(loading.find('[data-testid="list-state-loading"]').exists()).toBe(
      true
    );

    ScanSoloPipelineOpportunitiesAPI.get.mockResolvedValueOnce({ data: [] });
    const empty = mountBoard();
    await flushPromises();
    expect(empty.find('[data-testid="list-state-empty"]').text()).toBe(
      'Nenhuma oportunidade no pipeline ainda.'
    );

    ScanSoloPipelineOpportunitiesAPI.get.mockRejectedValueOnce(
      new Error('boom')
    );
    const failed = mountBoard();
    await flushPromises();
    expect(failed.find('[data-testid="list-state-error"]').exists()).toBe(true);
  });
});
