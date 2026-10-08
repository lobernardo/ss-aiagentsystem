import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import ScanSoloPipelineOpportunitiesAPI from 'dashboard/api/scansoloPipelineOpportunities';
import { useScansoloPipelineOpportunitiesStore } from 'dashboard/store/scansolo/pipelineOpportunities';
import { buildScanSoloSidebarItems } from '../../scansoloSidebarItems';
import KanbanBoard from '../KanbanBoard.vue';

vi.mock('dashboard/api/scansoloPipelineOpportunities', () => ({
  default: {
    get: vi.fn(),
    create: vi.fn(),
    stageTransition: vi.fn(),
  },
}));

const push = vi.fn();
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1 } }),
  useRouter: () => ({ push }),
}));

const openNewLeadDialog = vi.fn();
const NewLeadDialogStub = {
  name: 'NewLeadDialog',
  methods: { open: openNewLeadDialog },
  template: '<div data-testid="new-lead-dialog-stub" />',
};

const HOUR_MS = 60 * 60 * 1000;
const hoursAgo = hours => new Date(Date.now() - hours * HOUR_MS).toISOString();

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
      stubs: { NewLeadDialog: NewLeadDialogStub },
    },
  });

const cardFor = (wrapper, opportunityId) =>
  wrapper.find(
    `[data-testid="pipeline-card"][data-opportunity-id="${opportunityId}"]`
  );

const columnFor = (wrapper, stage) => wrapper.find(`[data-stage="${stage}"]`);

const mountWith = async opportunity => {
  ScanSoloPipelineOpportunitiesAPI.get.mockResolvedValue({
    data: [{ ...seededOpportunity, ...opportunity }],
  });
  const wrapper = mountBoard();
  await flushPromises();
  return cardFor(wrapper, seededOpportunity.id);
};

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

  describe('UI-01 / UI-02 / UI-03: lean card, navigation and "Novo lead"', () => {
    it('opens the "Novo lead" form from the header button', async () => {
      const wrapper = mountBoard();
      await flushPromises();

      const button = wrapper.find('[data-testid="new-lead-button"]');
      expect(button.text()).toBe('Novo lead');
      await button.trigger('click');

      expect(openNewLeadDialog).toHaveBeenCalledTimes(1);
    });

    it('shows origin, company, service, city/UF and the commercial status', async () => {
      const card = await mountWith({
        lead_source: 'website',
        company: 'Solar Ltda',
        service: 'Georradar',
        city_uf: 'Campinas/SP',
        quote_request_status: 'awaiting_reply',
        proposal_status: null,
      });

      expect(card.find('[data-testid="card-lead-source"]').text()).toBe('SITE');
      expect(card.find('[data-testid="card-title"]').text()).toBe('Solar Ltda');
      expect(card.find('[data-testid="card-service"]').text()).toBe(
        'Georradar'
      );
      expect(card.find('[data-testid="card-city-uf"]').text()).toBe(
        'Campinas/SP'
      );
      expect(card.find('[data-testid="card-commercial-status"]').text()).toBe(
        'Aguardando orçamento'
      );
    });

    it('shows the contact name and no tag, service, city or status when they are empty', async () => {
      const card = await mountWith({
        lead_source: null,
        company: null,
        service: null,
        city_uf: null,
        quote_request_status: null,
        proposal_status: null,
      });

      expect(card.find('[data-testid="card-title"]').text()).toBe(
        'Maria Silva'
      );
      expect(card.find('[data-testid="card-lead-source"]').exists()).toBe(
        false
      );
      expect(card.find('[data-testid="card-service"]').exists()).toBe(false);
      expect(card.find('[data-testid="card-city-uf"]').exists()).toBe(false);
      expect(card.find('[data-testid="card-commercial-status"]').exists()).toBe(
        false
      );
    });

    it('labels a generated proposal "Proposta gerada", never as sent (RF-33)', async () => {
      const card = await mountWith({
        quote_request_status: 'replied',
        proposal_status: 'generated',
      });

      expect(card.find('[data-testid="card-commercial-status"]').text()).toBe(
        'Proposta gerada'
      );
    });

    it('labels a proposal awaiting approval "Aguardando aprovação" (UI-03)', async () => {
      const card = await mountWith({
        quote_request_status: 'replied',
        proposal_status: 'awaiting_approval',
      });

      expect(card.find('[data-testid="card-commercial-status"]').text()).toBe(
        'Aguardando aprovação'
      );
    });

    it('labels a rejected proposal "Proposta rejeitada" (UI-03)', async () => {
      const card = await mountWith({
        quote_request_status: 'awaiting_reply',
        proposal_status: 'rejected',
      });

      expect(card.find('[data-testid="card-commercial-status"]').text()).toBe(
        'Proposta rejeitada'
      );
    });

    it('counts whole days without interaction: 49 hours → 2 days', async () => {
      const card = await mountWith({
        last_customer_interaction_at: hoursAgo(49),
      });

      expect(card.find('[data-testid="card-no-interaction"]').text()).toBe(
        'Sem interação há 2 dias'
      );
    });

    it('falls back to created_at and hides the counter below 1 day', async () => {
      const fromCreation = await mountWith({
        last_customer_interaction_at: null,
        created_at: hoursAgo(73),
      });
      expect(
        fromCreation.find('[data-testid="card-no-interaction"]').text()
      ).toBe('Sem interação há 3 dias');

      const recent = await mountWith({
        last_customer_interaction_at: hoursAgo(23),
      });
      expect(recent.find('[data-testid="card-no-interaction"]').exists()).toBe(
        false
      );
    });

    it('shows the human attendance indicator only outside ai_active', async () => {
      const human = await mountWith({ ai_control_state: 'awaiting_human' });
      expect(human.find('[data-testid="card-human-attendance"]').text()).toBe(
        'Atendimento humano'
      );

      const ai = await mountWith({ ai_control_state: 'ai_active' });
      expect(ai.find('[data-testid="card-human-attendance"]').exists()).toBe(
        false
      );
    });

    it('opens the opportunity detail on click', async () => {
      const card = await mountWith({});

      await card.trigger('click');

      expect(push).toHaveBeenCalledWith({
        name: 'scansolo_pipeline_opportunity_detail',
        params: { accountId: 1, opportunityId: seededOpportunity.id },
      });
    });

    it('keeps drag-and-drop moving the stage and never navigates while dragging', async () => {
      ScanSoloPipelineOpportunitiesAPI.stageTransition.mockResolvedValue({
        data: { ...seededOpportunity, stage: 'em_contato' },
      });
      const wrapper = mountBoard();
      await flushPromises();
      const card = cardFor(wrapper, seededOpportunity.id);

      await card.trigger('dragstart');
      await card.trigger('click');
      expect(push).not.toHaveBeenCalled();

      await columnFor(wrapper, 'em_contato').trigger('drop');
      await flushPromises();

      expect(
        ScanSoloPipelineOpportunitiesAPI.stageTransition
      ).toHaveBeenCalledWith(seededOpportunity.id, 'em_contato');
      expect(
        columnFor(wrapper, 'em_contato')
          .find(`[data-opportunity-id="${seededOpportunity.id}"]`)
          .exists()
      ).toBe(true);
    });

    it('shows a created manual lead in "Novo Lead" tagged COMERCIAL', async () => {
      ScanSoloPipelineOpportunitiesAPI.create.mockResolvedValue({
        data: {
          ...seededOpportunity,
          id: 2,
          contact_name: 'João Comercial',
          lead_source: 'manual',
          last_customer_interaction_at: null,
          created_at: new Date().toISOString(),
        },
      });
      const wrapper = mountBoard();
      await flushPromises();

      await useScansoloPipelineOpportunitiesStore().createOpportunity({
        name: 'João Comercial',
        phone_number: '+5511999999999',
      });
      await flushPromises();

      const card = columnFor(wrapper, 'novo_lead').find(
        '[data-opportunity-id="2"]'
      );
      expect(card.find('[data-testid="card-lead-source"]').text()).toBe(
        'COMERCIAL'
      );
      expect(card.find('[data-testid="card-title"]').text()).toBe(
        'João Comercial'
      );
    });

    it('leaves the ScanSolo menu items unchanged', () => {
      const items = buildScanSoloSidebarItems({
        t: key => key,
        accountScopedRoute: name => name,
      });

      expect(items.map(item => item.name)).toEqual([
        'ScanSolo pipeline',
        'ScanSolo agent',
        'ScanSolo knowledge',
        'ScanSolo followups',
        'ScanSolo proposals',
        'ScanSolo executions',
      ]);
    });
  });
});
