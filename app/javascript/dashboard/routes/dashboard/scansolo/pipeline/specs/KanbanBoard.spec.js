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

  it('scrolls the board horizontally with fixed-width columns for every stage', async () => {
    const wrapper = mountBoard();
    await flushPromises();

    const page = wrapper.find('[data-testid="scansolo-page-scroll"] > div');
    expect(page.classes()).toEqual(
      expect.arrayContaining(['flex', 'flex-col', 'h-full', 'min-h-0'])
    );
    const board = wrapper.find('[data-testid="pipeline-board"]');
    expect(board.classes()).toEqual(
      expect.arrayContaining(['flex', 'flex-1', 'min-h-0', 'overflow-x-auto'])
    );
    const columns = board.findAll('[data-testid="pipeline-column"]');
    expect(columns.map(column => column.attributes('data-stage'))).toEqual([
      'novo_lead',
      'em_contato',
      'em_qualificacao',
      'qualificado',
      'proposta_enviada',
      'negociacao',
      'ganho',
      'perdido',
    ]);
    columns.forEach(column => {
      expect(column.classes()).toEqual(
        expect.arrayContaining(['flex-shrink-0', 'w-72', 'min-h-0'])
      );
      expect(
        column.find('[data-testid="pipeline-column-cards"]').classes()
      ).toEqual(expect.arrayContaining(['min-h-0', 'overflow-y-auto']));
    });
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
        commercial_status: 'aguardando_artur',
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
        'Aguardando o Artur'
      );
    });

    it('shows the contact name and no tag, service, city or status when they are empty', async () => {
      const card = await mountWith({
        lead_source: null,
        company: null,
        service: null,
        city_uf: null,
        commercial_status: null,
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

    it.each([
      ['nao_encaminhado', 'Não encaminhado'],
      ['resposta_recebida', 'Resposta recebida'],
      ['proposta_em_aprovacao', 'Proposta em aprovação'],
      ['proposta_enviada', 'Proposta enviada'],
      ['proposta_enviada_manual', 'Proposta enviada manualmente'],
      ['escalado_wa', 'Encaminhado ao Artur (WhatsApp)'],
    ])(
      'labels the card from commercial_status %s (RF-03 / UI-07)',
      async (commercialStatus, label) => {
        // The quote/proposal statuses would read differently: the card must
        // follow the server's commercial_status only.
        const card = await mountWith({
          commercial_status: commercialStatus,
          quote_request_status: 'awaiting_reply',
          proposal_status: 'generated',
        });

        expect(card.find('[data-testid="card-commercial-status"]').text()).toBe(
          label
        );
      }
    );

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
        'ScanSolo reports',
      ]);
    });
  });
  describe('UI-06: commercial status filter', () => {
    const threeOpportunities = [
      { ...seededOpportunity, id: 1, commercial_status: 'aguardando_artur' },
      {
        ...seededOpportunity,
        id: 2,
        stage: 'qualificado',
        commercial_status: 'nao_encaminhado',
      },
      {
        ...seededOpportunity,
        id: 3,
        stage: 'proposta_enviada',
        commercial_status: 'proposta_enviada_manual',
      },
    ];

    const filterSelect = wrapper =>
      wrapper.find('[data-testid="commercial-status-filter"] select');

    beforeEach(() => {
      ScanSoloPipelineOpportunitiesAPI.get.mockResolvedValue({
        data: threeOpportunities,
      });
    });

    it('defaults to "Todas" and lists the 7 commercial statuses', async () => {
      const wrapper = mountBoard();
      await flushPromises();

      expect(filterSelect(wrapper).element.value).toBe('');
      expect(
        wrapper
          .findAll('[data-testid="commercial-status-filter"] option')
          .map(option => option.text())
      ).toEqual([
        'Todas',
        'Não encaminhado',
        'Aguardando o Artur',
        'Resposta recebida',
        'Proposta em aprovação',
        'Proposta enviada',
        'Proposta enviada manualmente',
        'Encaminhado ao Artur (WhatsApp)',
      ]);
      expect(wrapper.findAll('[data-testid="pipeline-card"]')).toHaveLength(3);
    });

    it('has 1 escalado_wa option that shows only the escalated cards', async () => {
      ScanSoloPipelineOpportunitiesAPI.get.mockResolvedValue({
        data: [
          ...threeOpportunities,
          {
            ...seededOpportunity,
            id: 4,
            stage: 'negociacao',
            commercial_status: 'escalado_wa',
          },
        ],
      });
      const wrapper = mountBoard();
      await flushPromises();

      const escalatedOptions = wrapper.findAll(
        '[data-testid="commercial-status-filter"] option[value="escalado_wa"]'
      );
      expect(escalatedOptions).toHaveLength(1);
      expect(escalatedOptions[0].text()).toContain('Artur');

      await filterSelect(wrapper).setValue('escalado_wa');
      const filtered = wrapper.findAll('[data-testid="pipeline-card"]');
      expect(filtered).toHaveLength(1);
      expect(filtered[0].attributes('data-opportunity-id')).toBe('4');
      expect(
        filtered[0].find('[data-testid="card-commercial-status"]').text()
      ).toBe('Encaminhado ao Artur (WhatsApp)');
    });

    it('shows only the matching cards, and all of them again in "Todas"', async () => {
      const wrapper = mountBoard();
      await flushPromises();

      await filterSelect(wrapper).setValue('aguardando_artur');
      const filtered = wrapper.findAll('[data-testid="pipeline-card"]');
      expect(filtered).toHaveLength(1);
      expect(filtered[0].attributes('data-opportunity-id')).toBe('1');

      await filterSelect(wrapper).setValue('');
      expect(wrapper.findAll('[data-testid="pipeline-card"]')).toHaveLength(3);
    });
  });

  describe('Relatórios RF-04: "Inativo" badge uses the stalled rule', () => {
    const MINUTE_MS = 60 * 1000;
    const minutesAgo = minutes =>
      new Date(Date.now() - minutes * MINUTE_MS).toISOString();
    const staleText = card => card.find('[data-testid="card-stale"]').text();

    it.each([
      [
        'interaction 47 h 59 min ago',
        { last_customer_interaction_at: minutesAgo(47 * 60 + 59) },
        '',
      ],
      [
        'interaction 48 h ago',
        { last_customer_interaction_at: minutesAgo(48 * 60) },
        'Inativo',
      ],
      [
        'no interaction, created 48 h ago',
        { last_customer_interaction_at: null, created_at: minutesAgo(48 * 60) },
        'Inativo',
      ],
      [
        'no interaction, created 47 h 59 min ago',
        {
          last_customer_interaction_at: null,
          created_at: minutesAgo(47 * 60 + 59),
        },
        '',
      ],
      [
        'ganho with the last interaction 30 days ago',
        { stage: 'ganho', last_customer_interaction_at: hoursAgo(30 * 24) },
        '',
      ],
      [
        'perdido with the last interaction 30 days ago',
        { stage: 'perdido', last_customer_interaction_at: hoursAgo(30 * 24) },
        '',
      ],
    ])('%s', async (_name, attributes, expected) => {
      const card = await mountWith(attributes);

      expect(staleText(card)).toBe(expected);
    });
  });

  describe('UI-08: single "proposta enviada manualmente" action on the card', () => {
    const button = card =>
      card.find('[data-testid="mark-handled-manually-button"]');

    it('shows the action only for aguardando_artur in qualificado/proposta_enviada', async () => {
      expect(
        button(
          await mountWith({
            stage: 'qualificado',
            commercial_status: 'aguardando_artur',
          })
        ).exists()
      ).toBe(true);
      expect(
        button(
          await mountWith({
            stage: 'qualificado',
            commercial_status: 'resposta_recebida',
          })
        ).exists()
      ).toBe(false);
    });

    it('never opens the lead when the action is clicked', async () => {
      const card = await mountWith({
        stage: 'qualificado',
        commercial_status: 'aguardando_artur',
      });

      await button(card).trigger('click');

      expect(push).not.toHaveBeenCalled();
    });
  });
});
