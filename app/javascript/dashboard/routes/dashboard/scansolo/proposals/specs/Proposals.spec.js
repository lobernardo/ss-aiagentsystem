import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import ScanSoloProposalsAPI from 'dashboard/api/scansoloProposals';
import Proposals from '../Proposals.vue';

vi.mock('dashboard/api/scansoloProposals', () => ({
  default: {
    get: vi.fn(),
    generate: vi.fn(),
    approve: vi.fn(),
    send: vi.fn(),
    retry: vi.fn(),
  },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

withFullI18n();
enableAutoUnmount(afterEach);

const OWNER_ID = 5;
const CORRELATION_ID = '8a6b2c1d-3e4f-4a5b-9c8d-7e6f5a4b3c2d';

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
  correlation_id: CORRELATION_ID,
  retry_count: 0,
  dead_letter: false,
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
  owner_id: OWNER_ID,
  integration_state: 'configured',
  current_version_id: 21,
  versions: [nonCurrentVersion, currentVersion],
};

const mountProposals = ({ role = 'administrator', userId = 1 } = {}) =>
  mount(Proposals, {
    global: {
      plugins: [
        createStore({
          getters: {
            getCurrentRole: () => role,
            getCurrentUser: () => ({ id: userId }),
          },
        }),
      ],
    },
  });

const withCurrentVersion = overrides => ({
  ...proposal,
  versions: [nonCurrentVersion, { ...currentVersion, ...overrides }],
});

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
    const wrapper = mountProposals();
    await flushPromises();

    const row = proposalRow(wrapper, proposal.id);
    expect(row.exists()).toBe(true);
    expect(row.find('[data-testid="proposal-contact-name"]').text()).toBe(
      'Maria Silva'
    );

    const current = versionRow(wrapper, currentVersion.id);
    expect(current.find('[data-testid="version-current-badge"]').text()).toBe(
      'Atual'
    );
    expect(current.find('[data-testid="version-status"]').text()).toBe(
      'Gerada'
    );

    const nonCurrent = versionRow(wrapper, nonCurrentVersion.id);
    expect(
      nonCurrent.find('[data-testid="version-current-badge"]').text()
    ).toBe('Anterior');
    expect(
      nonCurrent.find('[data-testid="version-approved-badge"]').exists()
    ).toBe(true);
  });

  it('shows an empty state when there are no proposals', async () => {
    ScanSoloProposalsAPI.get.mockResolvedValue({ data: [] });

    const wrapper = mountProposals();
    await flushPromises();

    expect(wrapper.find('[data-testid="list-state-empty"]').text()).toBe(
      'Nenhuma proposta gerada no momento.'
    );
  });

  it('disables the send action when the current version is unapproved and approval is required (UI-08)', async () => {
    const wrapper = mountProposals();
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

    const wrapper = mountProposals();
    await flushPromises();

    const sendButton = versionRow(wrapper, currentVersion.id).find(
      '[data-testid="send-button"]'
    );

    expect(sendButton.attributes('disabled')).toBeUndefined();
  });

  it('calls generate for the proposal opportunity', async () => {
    ScanSoloProposalsAPI.generate.mockResolvedValue({ data: currentVersion });

    const wrapper = mountProposals();
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

    const wrapper = mountProposals();
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
  describe('UI-13: buttons by role', () => {
    const visibleActions = wrapper => {
      const row = versionRow(wrapper, currentVersion.id);
      return {
        generate: proposalRow(wrapper, proposal.id)
          .find('[data-testid="generate-button"]')
          .exists(),
        approve: row.find('[data-testid="approve-button"]').exists(),
        send: row.find('[data-testid="send-button"]').exists(),
        retry: row.find('[data-testid="retry-button"]').exists(),
      };
    };

    beforeEach(() => {
      // A failed version shows retry to whoever may retry; a generated one shows approve.
      ScanSoloProposalsAPI.get.mockResolvedValue({ data: [proposal] });
    });

    it('agent non-owner sees generate only', async () => {
      const wrapper = mountProposals({ role: 'agent', userId: 99 });
      await flushPromises();

      expect(visibleActions(wrapper)).toEqual({
        generate: true,
        approve: false,
        send: false,
        retry: false,
      });
    });

    it('agent owner sees generate and send', async () => {
      const wrapper = mountProposals({ role: 'agent', userId: OWNER_ID });
      await flushPromises();

      expect(visibleActions(wrapper)).toEqual({
        generate: true,
        approve: false,
        send: true,
        retry: false,
      });
    });

    it('administrator sees generate, approve, send and retry', async () => {
      const wrapper = mountProposals();
      await flushPromises();
      expect(visibleActions(wrapper)).toMatchObject({
        generate: true,
        approve: true,
        send: true,
      });

      ScanSoloProposalsAPI.get.mockResolvedValue({
        data: [
          withCurrentVersion({ status: 'failed', failure_reason: 'timeout' }),
        ],
      });
      const failed = mountProposals();
      await flushPromises();
      expect(visibleActions(failed).retry).toBe(true);
    });

    it('agents see no correlation id', async () => {
      const wrapper = mountProposals({ role: 'agent', userId: OWNER_ID });
      await flushPromises();

      expect(wrapper.html()).not.toContain(CORRELATION_ID);
      expect(wrapper.find('[data-testid="technical-details"]').exists()).toBe(
        false
      );
    });
  });

  it('disables generate, send and retry with a pt-BR explanation while the integration is blocked', async () => {
    ScanSoloProposalsAPI.get.mockResolvedValue({
      data: [
        {
          ...withCurrentVersion({
            status: 'failed',
            failure_reason: 'timeout',
            approved_at: '2026-01-02T00:00:00Z',
          }),
          integration_state: 'blocked',
        },
      ],
    });
    const wrapper = mountProposals();
    await flushPromises();

    expect(
      wrapper.find('[data-testid="integration-blocked-notice"]').text()
    ).toContain(
      'integração de propostas com o Make ainda não está configurada'
    );
    const row = versionRow(wrapper, currentVersion.id);
    expect(
      proposalRow(wrapper, proposal.id)
        .find('[data-testid="generate-button"]')
        .attributes('disabled')
    ).toBeDefined();
    expect(
      row.find('[data-testid="send-button"]').attributes('disabled')
    ).toBeDefined();
    expect(
      row.find('[data-testid="retry-button"]').attributes('disabled')
    ).toBeDefined();
  });

  it('shows the failure reason of a failed version', async () => {
    ScanSoloProposalsAPI.get.mockResolvedValue({
      data: [
        withCurrentVersion({
          status: 'failed',
          failure_reason: 'provider_unavailable',
        }),
      ],
    });
    const wrapper = mountProposals({ role: 'agent', userId: 99 });
    await flushPromises();

    expect(
      versionRow(wrapper, currentVersion.id)
        .find('[data-testid="version-failure-reason"]')
        .text()
    ).toBe('Motivo da falha: Make indisponível');
  });

  it('asks for confirmation before sending and sends only after it', async () => {
    ScanSoloProposalsAPI.get.mockResolvedValue({
      data: [withCurrentVersion({ approved_at: '2026-01-02T00:00:00Z' })],
    });
    ScanSoloProposalsAPI.send.mockResolvedValue({ data: currentVersion });
    const wrapper = mountProposals();
    await flushPromises();

    await versionRow(wrapper, currentVersion.id)
      .find('[data-testid="send-button"]')
      .trigger('click');

    expect(ScanSoloProposalsAPI.send).not.toHaveBeenCalled();
    expect(
      wrapper.find('[data-testid="confirm-dialog-message"]').text()
    ).toContain('Enviar esta proposta ao cliente');

    await wrapper
      .find('[data-testid="confirm-dialog-confirm"]')
      .trigger('click');
    await flushPromises();

    expect(ScanSoloProposalsAPI.send).toHaveBeenCalledWith(
      proposal.id,
      currentVersion.id,
      expect.any(String)
    );
    expect(useAlert).toHaveBeenCalledWith('Envio de proposta solicitado.');
  });

  it('retries a failed version without confirmation', async () => {
    ScanSoloProposalsAPI.get.mockResolvedValue({
      data: [
        withCurrentVersion({ status: 'failed', failure_reason: 'timeout' }),
      ],
    });
    ScanSoloProposalsAPI.retry.mockResolvedValue({
      data: { ...currentVersion, status: 'generating', retry_count: 1 },
    });
    const wrapper = mountProposals();
    await flushPromises();

    await versionRow(wrapper, currentVersion.id)
      .find('[data-testid="retry-button"]')
      .trigger('click');
    await flushPromises();

    expect(ScanSoloProposalsAPI.retry).toHaveBeenCalledWith(
      proposal.id,
      currentVersion.id,
      false
    );
    expect(
      versionRow(wrapper, currentVersion.id)
        .find('[data-testid="version-status"]')
        .text()
    ).toBe('Gerando');
  });

  it('reprocesses a dead letter with confirm_reprocess only after confirmation', async () => {
    ScanSoloProposalsAPI.get.mockResolvedValue({
      data: [
        withCurrentVersion({
          status: 'failed',
          failure_reason: 'timeout',
          retry_count: 3,
          dead_letter: true,
        }),
      ],
    });
    ScanSoloProposalsAPI.retry.mockResolvedValue({ data: currentVersion });
    const wrapper = mountProposals();
    await flushPromises();
    const retryButton = versionRow(wrapper, currentVersion.id).find(
      '[data-testid="retry-button"]'
    );

    expect(retryButton.text()).toBe('Reprocessar');
    await retryButton.trigger('click');
    expect(ScanSoloProposalsAPI.retry).not.toHaveBeenCalled();
    expect(
      wrapper.find('[data-testid="confirm-dialog-message"]').text()
    ).toContain('3 vezes');

    await wrapper
      .find('[data-testid="confirm-dialog-confirm"]')
      .trigger('click');
    await flushPromises();

    expect(ScanSoloProposalsAPI.retry).toHaveBeenCalledWith(
      proposal.id,
      currentVersion.id,
      true
    );
  });

  it('renders the loading and error states and toasts action errors (UI-09)', async () => {
    ScanSoloProposalsAPI.get.mockReturnValueOnce(new Promise(() => {}));
    const loading = mountProposals();
    await flushPromises();
    expect(loading.find('[data-testid="list-state-loading"]').exists()).toBe(
      true
    );

    ScanSoloProposalsAPI.get.mockRejectedValueOnce(new Error('boom'));
    const failed = mountProposals();
    await flushPromises();
    expect(failed.find('[data-testid="list-state-error"]').exists()).toBe(true);

    ScanSoloProposalsAPI.generate.mockRejectedValue({
      response: { data: { error: 'proposal_integration_not_configured' } },
    });
    const wrapper = mountProposals();
    await flushPromises();
    await proposalRow(wrapper, proposal.id)
      .find('[data-testid="generate-button"]')
      .trigger('click');
    await flushPromises();
    expect(useAlert).toHaveBeenCalledWith(
      expect.stringContaining('ainda não está configurada')
    );
  });
});
