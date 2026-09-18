import { mount, flushPromises } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import ScanSoloProposalsAPI from 'dashboard/api/scansoloProposals';
import Proposals from '../Proposals.vue';

vi.mock('dashboard/api/scansoloProposals', () => ({
  default: {
    get: vi.fn(),
    generate: vi.fn(),
    approve: vi.fn(),
    send: vi.fn(),
  },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const currentVersion = {
  id: 21,
  proposal_id: 9,
  version_number: 2,
  status: 'generated',
  is_current: true,
  value: 1500.0,
  currency: 'BRL',
  artifact_url: 'https://x.test/a.pdf',
  approved_at: null,
  approval_required: true,
  failure_reason: null,
};

const nonCurrentVersion = {
  id: 20,
  proposal_id: 9,
  version_number: 1,
  status: 'sent',
  is_current: false,
  value: 1200.0,
  currency: 'BRL',
  approved_at: '2026-01-01T00:00:00Z',
  approval_required: true,
};

const proposal = {
  id: 9,
  opportunity_id: 5,
  contact_name: 'Maria Silva',
  current_version_id: 21,
  versions: [nonCurrentVersion, currentVersion],
};

const proposalRow = (wrapper, id) =>
  wrapper.find(`[data-testid="proposal-row"][data-proposal-id="${id}"]`);

const versionRow = (wrapper, id) =>
  wrapper.find(`[data-testid="proposal-version-row"][data-version-id="${id}"]`);

describe('Proposals', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    ScanSoloProposalsAPI.get.mockResolvedValue({ data: [proposal] });
  });

  it('shows proposal versions with current/non-current status and approval state (UI-08)', async () => {
    const wrapper = mount(Proposals);
    await flushPromises();

    const row = proposalRow(wrapper, proposal.id);
    expect(row.exists()).toBe(true);
    expect(row.find('[data-testid="proposal-contact-name"]').text()).toBe(
      'Maria Silva'
    );

    const current = versionRow(wrapper, currentVersion.id);
    expect(current.find('[data-testid="version-current-badge"]').text()).toBe(
      'SCANSOLO.PROPOSALS.CURRENT'
    );

    const nonCurrent = versionRow(wrapper, nonCurrentVersion.id);
    expect(
      nonCurrent.find('[data-testid="version-current-badge"]').text()
    ).toBe('SCANSOLO.PROPOSALS.NON_CURRENT');
    expect(
      nonCurrent.find('[data-testid="version-approved-badge"]').exists()
    ).toBe(true);
  });

  it('shows an empty state when there are no proposals', async () => {
    ScanSoloProposalsAPI.get.mockResolvedValue({ data: [] });

    const wrapper = mount(Proposals);
    await flushPromises();

    expect(wrapper.find('[data-testid="proposals-empty-state"]').exists()).toBe(
      true
    );
  });

  it('disables the send action when the current version is unapproved and approval is required (UI-08)', async () => {
    const wrapper = mount(Proposals);
    await flushPromises();

    const sendButton = versionRow(wrapper, currentVersion.id).find(
      '[data-testid="send-button"]'
    );

    expect(sendButton.attributes('disabled')).toBeDefined();
  });

  it('enables the send action once the current version is approved', async () => {
    ScanSoloProposalsAPI.get.mockResolvedValue({
      data: [
        {
          ...proposal,
          versions: [
            nonCurrentVersion,
            { ...currentVersion, approved_at: '2026-01-02T00:00:00Z' },
          ],
        },
      ],
    });

    const wrapper = mount(Proposals);
    await flushPromises();

    const sendButton = versionRow(wrapper, currentVersion.id).find(
      '[data-testid="send-button"]'
    );

    expect(sendButton.attributes('disabled')).toBeUndefined();
  });

  it('calls generate for the proposal opportunity', async () => {
    ScanSoloProposalsAPI.generate.mockResolvedValue({ data: currentVersion });

    const wrapper = mount(Proposals);
    await flushPromises();

    await proposalRow(wrapper, proposal.id)
      .find('[data-testid="generate-button"]')
      .trigger('click');
    await flushPromises();

    expect(ScanSoloProposalsAPI.generate).toHaveBeenCalledWith(
      proposal.opportunity_id,
      expect.any(String)
    );
  });

  it('calls approve for the current version and reflects the approved state', async () => {
    ScanSoloProposalsAPI.approve.mockResolvedValue({
      data: {
        ...currentVersion,
        status: 'approved',
        approved_at: '2026-01-03T00:00:00Z',
      },
    });

    const wrapper = mount(Proposals);
    await flushPromises();

    await versionRow(wrapper, currentVersion.id)
      .find('[data-testid="approve-button"]')
      .trigger('click');
    await flushPromises();

    expect(ScanSoloProposalsAPI.approve).toHaveBeenCalledWith(
      proposal.id,
      currentVersion.id,
      expect.any(String)
    );

    const sendButton = versionRow(wrapper, currentVersion.id).find(
      '[data-testid="send-button"]'
    );
    expect(sendButton.attributes('disabled')).toBeUndefined();
  });
});
