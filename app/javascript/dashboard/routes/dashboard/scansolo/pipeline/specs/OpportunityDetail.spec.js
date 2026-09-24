import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import ScanSoloPipelineOpportunitiesAPI from 'dashboard/api/scansoloPipelineOpportunities';
import OpportunityDetail from '../OpportunityDetail.vue';

vi.mock('dashboard/api/scansoloPipelineOpportunities', () => ({
  default: {
    show: vi.fn(),
  },
}));

const push = vi.fn();
vi.mock('vue-router', () => ({
  useRoute: () => ({
    params: { accountId: 1, opportunityId: 7 },
  }),
  useRouter: () => ({ push }),
}));

withFullI18n();
enableAutoUnmount(afterEach);

const ISO_PATTERN = /\d{4}-\d{2}-\d{2}T/;

const seededOpportunity = {
  id: 7,
  account_id: 1,
  contact_id: 3,
  contact_name: 'Ada Lovelace',
  conversation_id: 9,
  owner_id: 42,
  stage: 'em_qualificacao',
  last_customer_interaction_at: '2026-01-01T10:00:00Z',
  next_follow_up_at: null,
  stage_history: [
    {
      id: 1,
      from_stage: 'novo_lead',
      to_stage: 'em_contato',
      actor_type: null,
      actor_id: null,
      created_at: '2026-01-01T08:00:00Z',
    },
    {
      id: 2,
      from_stage: 'em_contato',
      to_stage: 'em_qualificacao',
      actor_type: 'User',
      actor_id: 5,
      created_at: '2026-01-01T09:00:00Z',
    },
  ],
};

const mountDetail = ({ role = 'administrator' } = {}) =>
  mount(OpportunityDetail, {
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

describe('OpportunityDetail', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    ScanSoloPipelineOpportunitiesAPI.show.mockResolvedValue({
      data: seededOpportunity,
    });
  });

  it('shows a chronological stage-history list matching the seeded PipelineStageEvent records', async () => {
    const wrapper = mountDetail();
    await flushPromises();

    expect(ScanSoloPipelineOpportunitiesAPI.show).toHaveBeenCalledWith(7);
    const items = wrapper.findAll('[data-testid="opportunity-history-item"]');
    expect(items).toHaveLength(2);
    expect(items[0].find('[data-testid="history-from-stage"]').text()).toBe(
      'Novo Lead'
    );
    expect(items[0].find('[data-testid="history-to-stage"]').text()).toBe(
      'Em Contato'
    );
    expect(items[1].find('[data-testid="history-from-stage"]').text()).toBe(
      'Em Contato'
    );
    expect(items[1].find('[data-testid="history-to-stage"]').text()).toBe(
      'Em Qualificação'
    );
    expect(
      items[0].find('[data-testid="history-created-at"]').attributes('title')
    ).toBe('01/01/2026 08:00');
  });

  it('shows the related contact and navigates to the related conversation', async () => {
    const wrapper = mountDetail();
    await flushPromises();

    expect(
      wrapper.find('[data-testid="opportunity-contact-name"]').text()
    ).toBe('Ada Lovelace');
    expect(wrapper.find('[data-testid="opportunity-stage"]').text()).toContain(
      'Em Qualificação'
    );

    await wrapper
      .find('[data-testid="opportunity-conversation-link"]')
      .trigger('click');

    expect(push).toHaveBeenCalledWith({
      name: 'inbox_conversation',
      params: { accountId: 1, conversation_id: 9 },
    });
  });

  it('shows an empty state when no stage history exists yet', async () => {
    ScanSoloPipelineOpportunitiesAPI.show.mockResolvedValue({
      data: { ...seededOpportunity, stage_history: [] },
    });

    const wrapper = mountDetail();
    await flushPromises();

    expect(
      wrapper.find('[data-testid="opportunity-history-empty"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="opportunity-history-list"]').exists()
    ).toBe(false);
  });

  it('hides owner id and ISO timestamps from agents and shows them to admins collapsed', async () => {
    const agentView = mountDetail({ role: 'agent' });
    await flushPromises();
    expect(agentView.html()).not.toMatch(ISO_PATTERN);
    expect(agentView.find('[data-testid="technical-details"]').exists()).toBe(
      false
    );

    const adminView = mountDetail();
    await flushPromises();
    const details = adminView.find('[data-testid="technical-details"]');
    expect(details.attributes('open')).toBeUndefined();
    expect(details.text()).toContain('42');
    expect(details.text()).toMatch(ISO_PATTERN);
  });

  it('renders the loading and error states (UI-09)', async () => {
    ScanSoloPipelineOpportunitiesAPI.show.mockReturnValueOnce(
      new Promise(() => {})
    );
    const loading = mountDetail();
    await flushPromises();
    expect(loading.find('[data-testid="list-state-loading"]').exists()).toBe(
      true
    );

    ScanSoloPipelineOpportunitiesAPI.show.mockRejectedValueOnce(
      new Error('boom')
    );
    const failed = mountDetail();
    await flushPromises();
    expect(failed.find('[data-testid="list-state-error"]').exists()).toBe(true);
  });
});
