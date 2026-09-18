import { mount, flushPromises } from '@vue/test-utils';
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

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

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

describe('OpportunityDetail', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('shows a chronological stage-history list matching the seeded PipelineStageEvent records', async () => {
    ScanSoloPipelineOpportunitiesAPI.show.mockResolvedValue({
      data: seededOpportunity,
    });

    const wrapper = mount(OpportunityDetail);
    await flushPromises();

    expect(ScanSoloPipelineOpportunitiesAPI.show).toHaveBeenCalledWith(7);

    const items = wrapper.findAll('[data-testid="opportunity-history-item"]');
    expect(items).toHaveLength(2);

    expect(items[0].find('[data-testid="history-from-stage"]').text()).toBe(
      'novo_lead'
    );
    expect(items[0].find('[data-testid="history-to-stage"]').text()).toBe(
      'em_contato'
    );
    expect(items[1].find('[data-testid="history-from-stage"]').text()).toBe(
      'em_contato'
    );
    expect(items[1].find('[data-testid="history-to-stage"]').text()).toBe(
      'em_qualificacao'
    );
  });

  it('shows the related contact and navigates to the related conversation', async () => {
    ScanSoloPipelineOpportunitiesAPI.show.mockResolvedValue({
      data: seededOpportunity,
    });

    const wrapper = mount(OpportunityDetail);
    await flushPromises();

    expect(
      wrapper.find('[data-testid="opportunity-contact-name"]').text()
    ).toBe('Ada Lovelace');

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

    const wrapper = mount(OpportunityDetail);
    await flushPromises();

    expect(
      wrapper.find('[data-testid="opportunity-history-empty"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="opportunity-history-list"]').exists()
    ).toBe(false);
  });
});
