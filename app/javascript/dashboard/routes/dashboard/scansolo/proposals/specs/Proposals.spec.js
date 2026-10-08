import {
  mount,
  flushPromises,
  enableAutoUnmount,
  DOMWrapper,
  RouterLinkStub,
} from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import ScanSoloProposalsAPI from 'dashboard/api/scansoloProposals';
import ScanSoloAiAgentConfigAPI from 'dashboard/api/scansoloAiAgentConfig';
import Proposals from '../Proposals.vue';

vi.mock('dashboard/api/scansoloProposals', () => ({
  default: {
    get: vi.fn(),
    generate: vi.fn(),
    approve: vi.fn(),
    reject: vi.fn(),
    send: vi.fn(),
    retry: vi.fn(),
  },
}));

vi.mock('dashboard/api/scansoloAiAgentConfig', () => ({
  default: { get: vi.fn() },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

withFullI18n();
enableAutoUnmount(afterEach);

const OWNER_ID = 5;
const COMMERCIAL_USER_ID = 7;
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

const QuoteRepliesPendingStub = {
  name: 'QuoteRepliesPending',
  template: '<section data-testid="quote-replies-pending-stub" />',
};

const mountProposals = ({ role = 'administrator', userId = 1 } = {}) =>
  mount(Proposals, {
    global: {
      plugins: [
        createStore({
          getters: {
            getCurrentRole: () => role,
            getCurrentUser: () => ({ id: userId }),
            'accounts/isRTL': () => false,
          },
        }),
      ],
      stubs: {
        QuoteRepliesPending: QuoteRepliesPendingStub,
        RouterLink: RouterLinkStub,
      },
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
    ScanSoloAiAgentConfigAPI.get.mockResolvedValue({
      data: {
        draft: { id: 1 },
        published: { id: 2, commercial_user_id: COMMERCIAL_USER_ID },
        available_models: [],
      },
    });
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

  // RF-55 (Etapa 1) / UI-06, expectation changed per RNF-11: the send
  // button no longer exists, approved or not.
  it('offers no send action for the current version, approved or not (RF-55 / UI-06)', async () => {
    ScanSoloProposalsAPI.get.mockResolvedValue({
      data: [
        proposal,
        {
          ...withCurrentVersion({ approved_at: '2026-01-02T00:00:00Z' }),
          id: 10,
        },
      ],
    });

    const wrapper = mountProposals();
    await flushPromises();

    expect(wrapper.findAll('[data-testid="send-button"]')).toHaveLength(0);
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

  // RF-55 (Etapa 1) / UI-06, expectation changed per RNF-11: the screen
  // no longer approves; the generated version stays read-only.
  it('offers no approve action for a generated version (RF-55 / UI-06)', async () => {
    const wrapper = mountProposals();
    await flushPromises();

    expect(
      versionRow(wrapper, currentVersion.id)
        .find('[data-testid="approve-button"]')
        .exists()
    ).toBe(false);
    expect(ScanSoloProposalsAPI.approve).not.toHaveBeenCalled();
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

    // RF-55 (Etapa 1) / UI-06, expectation changed per RNF-11: no send.
    it('agent owner sees generate only', async () => {
      const wrapper = mountProposals({ role: 'agent', userId: OWNER_ID });
      await flushPromises();

      expect(visibleActions(wrapper)).toEqual({
        generate: true,
        approve: false,
        send: false,
        retry: false,
      });
    });

    // RF-55 (Etapa 1) / UI-06, expectation changed per RNF-11: no approve
    // or send; retry stays for failed versions.
    it('administrator sees generate and, on a failed version, retry', async () => {
      const wrapper = mountProposals();
      await flushPromises();
      expect(visibleActions(wrapper)).toEqual({
        generate: true,
        approve: false,
        send: false,
        retry: false,
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

  // RF-55 (Etapa 1) / UI-06, expectation changed per RNF-11: the send
  // button is gone, so only generate and retry are disabled.
  it('disables generate and retry with a pt-BR explanation while the integration is blocked', async () => {
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

  // RF-55 (Etapa 1) / UI-06, expectation changed per RNF-11: the screen
  // never sends; the confirmation dialog only serves the dead-letter
  // reprocess.
  it('never exposes or calls send, even for an approved version (RF-55 / UI-06)', async () => {
    ScanSoloProposalsAPI.get.mockResolvedValue({
      data: [withCurrentVersion({ approved_at: '2026-01-02T00:00:00Z' })],
    });
    const wrapper = mountProposals();
    await flushPromises();

    expect(wrapper.find('[data-testid="send-button"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="confirm-dialog"]').exists()).toBe(false);
    expect(wrapper.vm.send).toBeUndefined();
    expect(wrapper.vm.approve).toBeUndefined();
    expect(ScanSoloProposalsAPI.send).not.toHaveBeenCalled();
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

  describe('UI-05 / UI-06: read-only versions and pending replies', () => {
    const historicalProposal = {
      ...proposal,
      quote_request_status: 'replied',
      versions: [
        {
          ...nonCurrentVersion,
          id: 30,
          version_number: 1,
          status: 'approved',
          approved_at: '2026-01-01T00:00:00Z',
          artifact_url: 'https://x.test/legacy.pdf',
        },
        {
          ...nonCurrentVersion,
          id: 31,
          version_number: 2,
          status: 'sent',
          sent_at: '2026-01-02T00:00:00Z',
        },
        {
          ...currentVersion,
          id: 32,
          version_number: 3,
          status: 'generated',
          proposal_number: 'SS-2026-0042',
          valid_until: '2026-02-15',
          document_url: 'https://chat.test/proposal.pdf',
        },
      ],
    };

    it('includes the pending replies section', async () => {
      const wrapper = mountProposals();
      await flushPromises();

      expect(
        wrapper.find('[data-testid="quote-replies-pending-stub"]').exists()
      ).toBe(true);
    });

    it('lists generated, approved and sent versions with their status and 0 approve/send buttons', async () => {
      ScanSoloProposalsAPI.get.mockResolvedValue({
        data: [historicalProposal],
      });
      const wrapper = mountProposals();
      await flushPromises();

      expect(
        [30, 31, 32].map(id =>
          versionRow(wrapper, id).find('[data-testid="version-status"]').text()
        )
      ).toEqual(['Aprovada', 'Enviada', 'Gerada']);
      expect(wrapper.findAll('[data-testid="approve-button"]')).toHaveLength(0);
      expect(wrapper.findAll('[data-testid="send-button"]')).toHaveLength(0);
      expect(wrapper.text()).not.toContain('Aprovar');
      expect(wrapper.text()).not.toMatch(/\bEnviar\b/);
    });

    it('shows the quote request status, number, validity and PDF link', async () => {
      ScanSoloProposalsAPI.get.mockResolvedValue({
        data: [historicalProposal],
      });
      const wrapper = mountProposals();
      await flushPromises();

      expect(
        wrapper.find('[data-testid="proposal-quote-request-status"]').text()
      ).toBe('Status do orçamento: Orçamento recebido');
      const current = versionRow(wrapper, 32);
      expect(
        current.find('[data-testid="version-proposal-number"]').text()
      ).toBe('Número: SS-2026-0042');
      expect(current.find('[data-testid="version-valid-until"]').text()).toBe(
        'Validade: 15/02/2026'
      );
      expect(
        current.find('[data-testid="version-document-link"]').attributes('href')
      ).toBe('https://chat.test/proposal.pdf');
      expect(
        versionRow(wrapper, 30)
          .find('[data-testid="version-document-link"]')
          .attributes('href')
      ).toBe('https://x.test/legacy.pdf');
    });

    it('shows "Reenviar" only on a failed version', async () => {
      ScanSoloProposalsAPI.get.mockResolvedValue({
        data: [
          withCurrentVersion({ status: 'failed', failure_reason: 'timeout' }),
        ],
      });
      const failed = mountProposals();
      await flushPromises();
      expect(
        versionRow(failed, currentVersion.id)
          .find('[data-testid="retry-button"]')
          .text()
      ).toBe('Reenviar');

      ScanSoloProposalsAPI.get.mockResolvedValue({
        data: [historicalProposal],
      });
      const generated = mountProposals();
      await flushPromises();
      expect(generated.findAll('[data-testid="retry-button"]')).toHaveLength(0);
    });
  });
  describe('UI-01: approve and reject an awaiting_approval version', () => {
    const awaitingVersion = {
      status: 'awaiting_approval',
      document_url: 'https://chat.test/proposal.pdf',
    };
    const dialog = () => new DOMWrapper(document.body.querySelector('dialog'));
    const reasonInput = () =>
      new DOMWrapper(
        document.body.querySelector('[data-testid="reject-reason-input"]')
      );
    const confirmButton = () =>
      new DOMWrapper(
        document.body.querySelector('dialog button[type="submit"]')
      );
    const actionButtons = wrapper => {
      const row = versionRow(wrapper, currentVersion.id);
      return {
        approve: row.find('[data-testid="approve-button"]'),
        reject: row.find('[data-testid="reject-button"]'),
      };
    };

    beforeEach(() => {
      // jsdom does not implement the native dialog lifecycle.
      Object.defineProperty(HTMLDialogElement.prototype, 'showModal', {
        configurable: true,
        value: function open() {
          this.setAttribute('open', '');
        },
      });
      Object.defineProperty(HTMLDialogElement.prototype, 'close', {
        configurable: true,
        value: function close() {
          if (!this.open) return;
          this.removeAttribute('open');
          this.dispatchEvent(new Event('close'));
        },
      });
      ScanSoloProposalsAPI.get.mockResolvedValue({
        data: [
          {
            ...withCurrentVersion(awaitingVersion),
            lead_email_present: true,
          },
        ],
      });
    });

    afterEach(() => {
      delete HTMLDialogElement.prototype.showModal;
      delete HTMLDialogElement.prototype.close;
      document.body.innerHTML = '';
    });

    it('shows Aprovar and Rejeitar with the "Aguardando aprovação" status to an administrator', async () => {
      const wrapper = mountProposals();
      await flushPromises();

      const { approve, reject } = actionButtons(wrapper);
      expect(approve.text()).toBe('Aprovar');
      expect(approve.attributes('disabled')).toBeUndefined();
      expect(reject.text()).toBe('Rejeitar');
      expect(
        versionRow(wrapper, currentVersion.id)
          .find('[data-testid="version-status"]')
          .text()
      ).toBe('Aguardando aprovação');
      expect(wrapper.findAll('[data-testid="send-button"]')).toHaveLength(0);
    });

    it('shows Aprovar and Rejeitar to the published commercial agent', async () => {
      const wrapper = mountProposals({
        role: 'agent',
        userId: COMMERCIAL_USER_ID,
      });
      await flushPromises();

      const { approve, reject } = actionButtons(wrapper);
      expect(approve.exists()).toBe(true);
      expect(reject.exists()).toBe(true);
    });

    it('hides Aprovar and Rejeitar from an agent that is not the commercial user', async () => {
      const wrapper = mountProposals({ role: 'agent', userId: OWNER_ID });
      await flushPromises();

      expect(wrapper.findAll('[data-testid="approve-button"]')).toHaveLength(0);
      expect(wrapper.findAll('[data-testid="reject-button"]')).toHaveLength(0);
    });

    it('approves with 1 POST approve and shows the new status', async () => {
      ScanSoloProposalsAPI.approve.mockResolvedValue({
        data: {
          ...currentVersion,
          ...awaitingVersion,
          status: 'approved',
          approved_at: '2026-10-08T00:00:00Z',
        },
      });
      const wrapper = mountProposals();
      await flushPromises();

      await actionButtons(wrapper).approve.trigger('click');
      await flushPromises();

      expect(ScanSoloProposalsAPI.approve).toHaveBeenCalledTimes(1);
      expect(ScanSoloProposalsAPI.approve).toHaveBeenCalledWith(
        proposal.id,
        currentVersion.id,
        expect.any(String)
      );
      expect(
        versionRow(wrapper, currentVersion.id)
          .find('[data-testid="version-status"]')
          .text()
      ).toBe('Aprovada');
      expect(wrapper.findAll('[data-testid="approve-button"]')).toHaveLength(0);
    });

    it('rejects with a reason through the dialog with 1 POST reject', async () => {
      ScanSoloProposalsAPI.reject.mockResolvedValue({
        data: {
          ...currentVersion,
          status: 'rejected',
          rejection_reason: 'Valor errado',
        },
      });
      const wrapper = mountProposals();
      await flushPromises();

      await actionButtons(wrapper).reject.trigger('click');
      expect(dialog().attributes('open')).toBeDefined();
      await reasonInput().setValue('Valor errado');
      await confirmButton().trigger('submit');
      await flushPromises();

      expect(ScanSoloProposalsAPI.reject).toHaveBeenCalledTimes(1);
      expect(ScanSoloProposalsAPI.reject).toHaveBeenCalledWith(
        proposal.id,
        currentVersion.id,
        'Valor errado'
      );
      expect(dialog().attributes('open')).toBeUndefined();
      const row = versionRow(wrapper, currentVersion.id);
      expect(row.find('[data-testid="version-status"]').text()).toBe(
        'Rejeitada'
      );
      expect(row.find('[data-testid="version-rejection-reason"]').text()).toBe(
        'Motivo da rejeição: Valor errado'
      );
    });

    it('keeps confirm disabled and sends 0 requests with an empty reason', async () => {
      const wrapper = mountProposals();
      await flushPromises();

      await actionButtons(wrapper).reject.trigger('click');
      await reasonInput().setValue('   ');

      expect(confirmButton().attributes('disabled')).toBeDefined();
      await dialog().find('form').trigger('submit');
      await flushPromises();

      expect(ScanSoloProposalsAPI.reject).not.toHaveBeenCalled();
    });

    it('disables Aprovar with a notice and a link to the lead screen without a lead e-mail (RF-08)', async () => {
      ScanSoloProposalsAPI.get.mockResolvedValue({
        data: [
          {
            ...withCurrentVersion(awaitingVersion),
            lead_email_present: false,
          },
        ],
      });
      const wrapper = mountProposals();
      await flushPromises();

      expect(
        actionButtons(wrapper).approve.attributes('disabled')
      ).toBeDefined();
      const notice = wrapper.find('[data-testid="lead-email-missing-notice"]');
      expect(notice.text()).toContain('Falta o e-mail do lead');
      expect(wrapper.findComponent(RouterLinkStub).props('to')).toEqual({
        name: 'scansolo_pipeline_opportunity_detail',
        params: { opportunityId: proposal.opportunity_id },
      });
    });

    it('disables Aprovar while the PDF is not stored yet', async () => {
      ScanSoloProposalsAPI.get.mockResolvedValue({
        data: [
          {
            ...withCurrentVersion({ ...awaitingVersion, document_url: null }),
            lead_email_present: true,
          },
        ],
      });
      const wrapper = mountProposals();
      await flushPromises();

      expect(
        actionButtons(wrapper).approve.attributes('disabled')
      ).toBeDefined();
      expect(
        wrapper.find('[data-testid="document-pending-notice"]').exists()
      ).toBe(true);
    });

    it('shows a 422 error by its code', async () => {
      ScanSoloProposalsAPI.approve.mockRejectedValue({
        response: { status: 422, data: { error: 'lead_email_missing' } },
      });
      const wrapper = mountProposals();
      await flushPromises();

      await actionButtons(wrapper).approve.trigger('click');
      await flushPromises();

      expect(useAlert).toHaveBeenCalledWith(
        'Falta o e-mail do lead. Cadastre o e-mail na tela do lead e tente novamente.'
      );
    });

    it('offers 0 action buttons on a sent version and shows its delivery', async () => {
      ScanSoloProposalsAPI.get.mockResolvedValue({
        data: [
          {
            ...withCurrentVersion({
              status: 'sent',
              approved_at: '2026-10-08T00:00:00Z',
              delivery: { email_status: 'sent', notice_status: 'pending' },
            }),
            lead_email_present: true,
          },
        ],
      });
      const wrapper = mountProposals();
      await flushPromises();

      const row = versionRow(wrapper, currentVersion.id);
      expect(row.findAll('button')).toHaveLength(0);
      expect(row.find('[data-testid="version-status"]').text()).toBe('Enviada');
      expect(row.find('[data-testid="version-delivery"]').text()).toContain(
        'E-mail ao lead Enviado'
      );
    });

    it('shows a delivery failure with its reason and offers Reenviar to the commercial agent (RF-15)', async () => {
      ScanSoloProposalsAPI.get.mockResolvedValue({
        data: [
          withCurrentVersion({
            status: 'failed',
            failure_reason: 'email_delivery_failed',
            delivery: { email_status: 'failed', notice_status: null },
          }),
        ],
      });
      const wrapper = mountProposals({
        role: 'agent',
        userId: COMMERCIAL_USER_ID,
      });
      await flushPromises();

      const row = versionRow(wrapper, currentVersion.id);
      expect(row.find('[data-testid="version-failure-reason"]').text()).toBe(
        'Motivo da falha: Falha no envio do e-mail ao lead'
      );
      expect(row.find('[data-testid="version-delivery-email"]').text()).toBe(
        'E-mail ao lead Falhou'
      );
      expect(row.find('[data-testid="retry-button"]').text()).toBe('Reenviar');
    });
  });
});
