import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import { onBeforeRouteLeave } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import ScanSoloAiAgentConfigAPI from 'dashboard/api/scansoloAiAgentConfig';
import { buildScanSoloSidebarItems } from '../../scansoloSidebarItems';
import AgentCenter from '../AgentCenter.vue';

vi.mock('dashboard/api/scansoloAiAgentConfig', () => ({
  default: {
    get: vi.fn(),
    updateDraft: vi.fn(),
    publish: vi.fn(),
  },
}));

vi.mock('vue-router', () => ({ onBeforeRouteLeave: vi.fn() }));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

withFullI18n();
enableAutoUnmount(afterEach);

const draftFixture = {
  id: 1,
  status: 'draft',
  name: 'Agente v1',
  enabled: true,
  model_provider: 'openai',
  model_selection: 'gpt-4.1',
  role: 'SDR virtual',
  objective: 'Qualificar leads',
  persona: 'Consultivo',
  tone: 'Profissional',
  instructions: 'Responda em pt-BR',
  service_rules: 'Nunca prometa desconto',
  qualification_playbook: ['orcamento', 'prazo'],
  required_qualification_fields: ['orcamento'],
  restricted_information: ['preco_interno'],
  forbidden_subjects: ['concorrentes'],
  transfer_criteria: 'Cliente pede humano',
  response_limits: 'Ate 3 mensagens por turno',
  service_hours: '09:00-20:00 America/Sao_Paulo',
  require_proposal_approval: true,
  allowed_inbox_ids: [12],
  opt_out_keywords: ['PARAR', 'SAIR', 'STOP'],
  quote_inbox_id: null,
  commercial_user_id: null,
  quote_recipient_email: 'comercial@scansolo.com.br',
  updated_at: '2026-01-01T09:00:00Z',
};

const inboxesFixture = [
  { id: 11, name: 'WhatsApp Vendas' },
  { id: 12, name: 'WhatsApp Suporte' },
];

const emailInbox = {
  id: 13,
  name: 'Comercial E-mail',
  channel_type: 'Channel::Email',
};

const agentsFixture = [
  { id: 7, name: 'Luciano Comercial' },
  { id: 8, name: 'Carla Vendas' },
];

const AVAILABLE_MODELS = ['gpt-4.1-mini', 'gpt-4.1', 'gpt-5.1', 'gpt-5.2'];

const mountAgentCenter = ({
  role = 'administrator',
  inboxes = inboxesFixture,
} = {}) =>
  mount(AgentCenter, {
    global: {
      plugins: [
        createStore({
          getters: {
            'inboxes/getInboxes': () => inboxes,
            'agents/getAgents': () => agentsFixture,
            getCurrentRole: () => role,
            getCurrentUser: () => ({ id: 5 }),
          },
          actions: { 'agents/get': vi.fn() },
        }),
      ],
    },
  });

const deferred = () => {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
};

const routeLeaveGuard = () => onBeforeRouteLeave.mock.calls.at(-1)[0];

describe('AgentCenter', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    ScanSoloAiAgentConfigAPI.get.mockResolvedValue({
      data: {
        draft: draftFixture,
        published: null,
        available_models: AVAILABLE_MODELS,
      },
    });
  });

  it('exposes every RF-20 field', async () => {
    const wrapper = mountAgentCenter();
    await flushPromises();

    [
      'name',
      'enabled',
      'modelProvider',
      'modelSelection',
      'role',
      'objective',
      'persona',
      'tone',
      'instructions',
      'serviceRules',
      'qualificationPlaybook',
      'requiredQualificationFields',
      'restrictedInformation',
      'forbiddenSubjects',
      'transferCriteria',
      'responseLimits',
      'serviceHours',
    ].forEach(field => {
      expect(wrapper.find(`[data-testid="field-${field}"]`).exists()).toBe(
        true
      );
    });
  });

  it('renders translated labels, never raw i18n keys', async () => {
    const wrapper = mountAgentCenter();
    await flushPromises();

    expect(wrapper.text()).not.toContain('SCANSOLO.');
    expect(wrapper.text()).toContain('Provedor do modelo');
    expect(wrapper.text()).toContain('Campos obrigatórios de qualificação');
  });

  it('shows a visible draft-vs-published indicator', async () => {
    const wrapper = mountAgentCenter();
    await flushPromises();

    expect(wrapper.find('[data-testid="agent-status-indicator"]').text()).toBe(
      'Ainda não publicado'
    );

    ScanSoloAiAgentConfigAPI.get.mockResolvedValue({
      data: {
        draft: draftFixture,
        published: { ...draftFixture, status: 'published' },
      },
    });
    const publishedWrapper = mountAgentCenter();
    await flushPromises();

    expect(
      publishedWrapper.find('[data-testid="agent-status-indicator"]').text()
    ).toBe('Publicado');
  });

  it('blocks accidental publish: clicking Publish only opens a confirmation, it does not call the API', async () => {
    const wrapper = mountAgentCenter();
    await flushPromises();

    await wrapper.find('[data-testid="publish-button"]').trigger('click');

    expect(
      wrapper.find('[data-testid="publish-confirm-dialog"]').exists()
    ).toBe(true);
    expect(ScanSoloAiAgentConfigAPI.publish).not.toHaveBeenCalled();
  });

  it('only publishes after the explicit confirmation click', async () => {
    ScanSoloAiAgentConfigAPI.publish.mockResolvedValue({
      data: { ...draftFixture, status: 'published' },
    });

    const wrapper = mountAgentCenter();
    await flushPromises();

    await wrapper.find('[data-testid="publish-button"]').trigger('click');
    await wrapper
      .find('[data-testid="publish-confirm-button"]')
      .trigger('click');
    await flushPromises();

    expect(ScanSoloAiAgentConfigAPI.publish).toHaveBeenCalledTimes(1);
    expect(
      wrapper.find('[data-testid="publish-confirm-dialog"]').exists()
    ).toBe(false);
  });

  it('cancelling the confirmation dialog never publishes', async () => {
    const wrapper = mountAgentCenter();
    await flushPromises();

    await wrapper.find('[data-testid="publish-button"]').trigger('click');
    await wrapper
      .find('[data-testid="publish-cancel-button"]')
      .trigger('click');

    expect(
      wrapper.find('[data-testid="publish-confirm-dialog"]').exists()
    ).toBe(false);
    expect(ScanSoloAiAgentConfigAPI.publish).not.toHaveBeenCalled();
  });

  it('saves the draft without requiring publish confirmation', async () => {
    ScanSoloAiAgentConfigAPI.updateDraft.mockResolvedValue({
      data: { ...draftFixture, name: 'Agente v1 editado' },
    });

    const wrapper = mountAgentCenter();
    await flushPromises();

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(ScanSoloAiAgentConfigAPI.updateDraft).toHaveBeenCalledTimes(1);
    expect(ScanSoloAiAgentConfigAPI.publish).not.toHaveBeenCalled();
  });

  // RF-54 / UI-06, expectation changed per RNF-11: "Proposta" (approval
  // toggle) gives way to "Comercial" (quote routing fields).
  it('organizes the form into the 9 sections in order', async () => {
    const wrapper = mountAgentCenter();
    await flushPromises();

    expect(wrapper.findAll('form h2').map(heading => heading.text())).toEqual([
      'Identidade',
      'Modelo',
      'Comportamento',
      'Qualificação',
      'Segurança',
      'Handoff',
      'Horário',
      'Comercial',
      'Canais',
    ]);
  });

  it('lists the account inboxes by name in the Canais multi-select', async () => {
    const wrapper = mountAgentCenter();
    await flushPromises();
    const channels = wrapper.find('[data-testid="field-allowedInboxIds"]');

    expect(channels.text()).toContain('WhatsApp Suporte');

    await channels.find('.cursor-pointer').trigger('click');
    const optionLabels = channels
      .findAll('li[role="option"]')
      .map(option => option.text());

    expect(optionLabels).toEqual(['WhatsApp Vendas', 'WhatsApp Suporte']);
    expect(channels.text()).not.toMatch(/\b1[12]\b/);
  });

  it('saves the selected inboxes as allowed_inbox_ids', async () => {
    ScanSoloAiAgentConfigAPI.updateDraft.mockResolvedValue({
      data: { ...draftFixture, allowed_inbox_ids: [12, 11] },
    });
    const wrapper = mountAgentCenter();
    await flushPromises();
    const channels = wrapper.find('[data-testid="field-allowedInboxIds"]');

    await channels.find('.cursor-pointer').trigger('click');
    await channels.findAll('li[role="option"]')[0].trigger('click');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    // RF-55 Etapa 1 / UI-06, expectation changed per RNF-11: the payload
    // no longer carries require_proposal_approval.
    expect(ScanSoloAiAgentConfigAPI.updateDraft).toHaveBeenCalledWith(
      expect.objectContaining({ allowed_inbox_ids: [12, 11] })
    );
    expect(
      ScanSoloAiAgentConfigAPI.updateDraft.mock.calls[0][0]
    ).not.toHaveProperty('require_proposal_approval');
  });
  describe('UI-05: save and publish feedback', () => {
    it('disables both buttons while the save request is pending, then toasts success', async () => {
      const request = deferred();
      ScanSoloAiAgentConfigAPI.updateDraft.mockReturnValue(request.promise);
      const wrapper = mountAgentCenter();
      await flushPromises();

      await wrapper.find('form').trigger('submit');

      expect(
        wrapper.find('[data-testid="save-draft-button"]').attributes('disabled')
      ).toBeDefined();
      expect(
        wrapper.find('[data-testid="publish-button"]').attributes('disabled')
      ).toBeDefined();

      request.resolve({ data: draftFixture });
      await flushPromises();

      expect(
        wrapper.find('[data-testid="save-draft-button"]').attributes('disabled')
      ).toBeUndefined();
      expect(useAlert).toHaveBeenCalledWith('Rascunho salvo.');
    });

    it('toasts the server message when saving fails', async () => {
      ScanSoloAiAgentConfigAPI.updateDraft.mockRejectedValue({
        response: {
          data: { message: 'Model selection is not an available model' },
        },
      });
      const wrapper = mountAgentCenter();
      await flushPromises();

      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(useAlert).toHaveBeenCalledWith(
        'Model selection is not an available model'
      );
    });

    it('keeps the publish confirmation and toasts the publish result', async () => {
      const request = deferred();
      ScanSoloAiAgentConfigAPI.publish.mockReturnValue(request.promise);
      const wrapper = mountAgentCenter();
      await flushPromises();

      await wrapper.find('[data-testid="publish-button"]').trigger('click');
      await wrapper
        .find('[data-testid="publish-confirm-button"]')
        .trigger('click');

      expect(
        wrapper.find('[data-testid="save-draft-button"]').attributes('disabled')
      ).toBeDefined();

      request.reject({ response: { data: { error: 'forbidden' } } });
      await flushPromises();

      expect(useAlert).toHaveBeenCalledWith('forbidden');
      expect(
        wrapper.find('[data-testid="publish-button"]').attributes('disabled')
      ).toBeUndefined();
    });

    it('toasts success after publishing', async () => {
      ScanSoloAiAgentConfigAPI.publish.mockResolvedValue({
        data: { ...draftFixture, status: 'published' },
      });
      const wrapper = mountAgentCenter();
      await flushPromises();

      await wrapper.find('[data-testid="publish-button"]').trigger('click');
      await wrapper
        .find('[data-testid="publish-confirm-button"]')
        .trigger('click');
      await flushPromises();

      expect(useAlert).toHaveBeenCalledWith('Configuração publicada.');
    });
  });

  describe('UI-06: unsaved changes', () => {
    it('asks for confirmation before leaving with a dirty form', async () => {
      const wrapper = mountAgentCenter();
      await flushPromises();

      await wrapper.find('[data-testid="field-name"]').setValue('Outro nome');
      const leave = routeLeaveGuard()();
      await flushPromises();

      expect(
        wrapper.find('[data-testid="unsaved-changes-dialog"]').text()
      ).toContain('Há alterações não salvas');

      await wrapper
        .find(
          '[data-testid="unsaved-changes-dialog"] [data-testid="confirm-dialog-cancel"]'
        )
        .trigger('click');
      await expect(leave).resolves.toBe(false);
    });

    it('lets the route change through with a clean form', async () => {
      const wrapper = mountAgentCenter();
      await flushPromises();

      expect(routeLeaveGuard()()).toBe(true);
      expect(
        wrapper.find('[data-testid="unsaved-changes-dialog"]').exists()
      ).toBe(false);
    });

    it('blocks closing the tab only while the form is dirty', async () => {
      const wrapper = mountAgentCenter();
      await flushPromises();
      const cleanEvent = new Event('beforeunload', { cancelable: true });
      window.dispatchEvent(cleanEvent);
      expect(cleanEvent.defaultPrevented).toBe(false);

      await wrapper.find('[data-testid="field-tone"]').setValue('Descontraído');
      const dirtyEvent = new Event('beforeunload', { cancelable: true });
      window.dispatchEvent(dirtyEvent);

      expect(dirtyEvent.defaultPrevented).toBe(true);
    });
  });

  describe('UI-06 / UI-08: no approval toggle and model selects', () => {
    // RF-55 Etapa 1 / UI-06, expectation changed per RNF-11: the approval
    // toggle is no longer displayed nor sent.
    it('shows 0 approval toggles and never sends require_proposal_approval', async () => {
      ScanSoloAiAgentConfigAPI.updateDraft.mockResolvedValue({
        data: draftFixture,
      });
      const wrapper = mountAgentCenter();
      await flushPromises();

      expect(
        wrapper.find('[data-testid="field-requireProposalApproval"]').exists()
      ).toBe(false);
      expect(wrapper.find('[data-testid="section-proposal"]').exists()).toBe(
        false
      );
      expect(wrapper.text()).not.toContain('Exigir aprovação');

      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(
        ScanSoloAiAgentConfigAPI.updateDraft.mock.calls[0][0]
      ).not.toHaveProperty('require_proposal_approval');
    });

    it('lists the 4 server models and the provider in selects', async () => {
      const wrapper = mountAgentCenter();
      await flushPromises();

      const models = wrapper
        .findAll('[data-testid="field-modelSelection"] option:not([disabled])')
        .map(option => option.text());
      expect(models).toEqual(AVAILABLE_MODELS);
      expect(
        wrapper.find('[data-testid="field-modelSelection"]').element.value
      ).toBe('gpt-4.1');
      expect(
        wrapper.find('[data-testid="field-modelProvider"]').text()
      ).toContain('OpenAI');
    });
  });

  describe('UI-14: opt-out keywords', () => {
    it('shows the default keywords in the Segurança section and sends a new entry in the draft', async () => {
      ScanSoloAiAgentConfigAPI.updateDraft.mockResolvedValue({
        data: draftFixture,
      });
      const wrapper = mountAgentCenter();
      await flushPromises();
      const field = wrapper.find(
        '[data-testid="section-safety"] [data-testid="field-optOutKeywords"]'
      );

      expect(
        field.findAll('[data-testid="opt-out-keyword"]').map(k => k.text())
      ).toEqual(
        expect.arrayContaining([
          expect.stringContaining('PARAR'),
          expect.stringContaining('SAIR'),
          expect.stringContaining('STOP'),
        ])
      );

      await field
        .find('[data-testid="new-opt-out-keyword"]')
        .setValue('CANCELAR');
      await field.find('[data-testid="add-opt-out-keyword"]').trigger('click');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(ScanSoloAiAgentConfigAPI.updateDraft).toHaveBeenCalledWith(
        expect.objectContaining({
          opt_out_keywords: ['PARAR', 'SAIR', 'STOP', 'CANCELAR'],
        })
      );
    });

    it('shows the keywords read-only to agents', async () => {
      const wrapper = mountAgentCenter({ role: 'agent' });
      await flushPromises();
      const field = wrapper.find('[data-testid="field-optOutKeywords"]');

      expect(field.findAll('[data-testid="opt-out-keyword"]')).toHaveLength(3);
      expect(field.find('[data-testid="new-opt-out-keyword"]').exists()).toBe(
        false
      );
      expect(
        field.find('[data-testid="remove-opt-out-keyword"]').exists()
      ).toBe(false);
      expect(wrapper.find('[data-testid="save-draft-button"]').exists()).toBe(
        false
      );
      expect(
        wrapper.find('[data-testid="agent-read-only-notice"]').exists()
      ).toBe(true);
    });
  });

  describe('UI-09: loading and error states', () => {
    it('renders the loading state while the config is fetched', async () => {
      ScanSoloAiAgentConfigAPI.get.mockReturnValue(new Promise(() => {}));
      const wrapper = mountAgentCenter();
      await flushPromises();

      expect(wrapper.find('[data-testid="list-state-loading"]').exists()).toBe(
        true
      );
      expect(wrapper.find('form').exists()).toBe(false);
    });

    it('renders the error state when the config fails to load', async () => {
      ScanSoloAiAgentConfigAPI.get.mockRejectedValue(new Error('boom'));
      const wrapper = mountAgentCenter();
      await flushPromises();

      expect(wrapper.find('[data-testid="list-state-error"]').exists()).toBe(
        true
      );
    });
  });

  describe('RF-54: commercial routing fields', () => {
    const commercial = wrapper =>
      wrapper.find('[data-testid="section-commercial"]');

    it('shows the quote inbox, commercial user and recipient e-mail fields', async () => {
      const wrapper = mountAgentCenter({
        inboxes: [...inboxesFixture, emailInbox],
      });
      await flushPromises();
      const section = commercial(wrapper);

      expect(section.text()).toContain('Inbox de e-mail de orçamento');
      expect(section.text()).toContain('Usuário comercial responsável');
      expect(section.text()).toContain('E-mail do destinatário comercial');
      expect(
        section
          .findAll('[data-testid="field-quoteInboxId"] option')
          .map(option => option.text())
      ).toEqual(['Selecione a caixa de entrada de e-mail', 'Comercial E-mail']);
      expect(
        section
          .findAll('[data-testid="field-commercialUserId"] option')
          .map(option => option.text())
      ).toEqual([
        'Selecione o usuário comercial',
        'Luciano Comercial',
        'Carla Vendas',
      ]);
      expect(
        section.find('[data-testid="field-quoteRecipientEmail"]').element.value
      ).toBe('comercial@scansolo.com.br');
    });

    it('sends the 3 fields when saving', async () => {
      ScanSoloAiAgentConfigAPI.updateDraft.mockResolvedValue({
        data: draftFixture,
      });
      const wrapper = mountAgentCenter({
        inboxes: [...inboxesFixture, emailInbox],
      });
      await flushPromises();
      const section = commercial(wrapper);

      await section.find('[data-testid="field-quoteInboxId"]').setValue(13);
      await section.find('[data-testid="field-commercialUserId"]').setValue(7);
      await section
        .find('[data-testid="field-quoteRecipientEmail"]')
        .setValue('luciano@scansolo.com.br');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(ScanSoloAiAgentConfigAPI.updateDraft).toHaveBeenCalledWith(
        expect.objectContaining({
          quote_inbox_id: 13,
          commercial_user_id: 7,
          quote_recipient_email: 'luciano@scansolo.com.br',
        })
      );
    });

    it('blocks saving with an empty recipient: field error and 0 requests', async () => {
      const wrapper = mountAgentCenter();
      await flushPromises();

      await commercial(wrapper)
        .find('[data-testid="field-quoteRecipientEmail"]')
        .setValue('');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(ScanSoloAiAgentConfigAPI.updateDraft).not.toHaveBeenCalled();
      expect(
        wrapper.find('[data-testid="field-error-quoteRecipientEmail"]').text()
      ).toBe('Informe um e-mail válido para o destinatário comercial.');
    });

    it('rejects a malformed recipient e-mail locally', async () => {
      const wrapper = mountAgentCenter();
      await flushPromises();

      await commercial(wrapper)
        .find('[data-testid="field-quoteRecipientEmail"]')
        .setValue('comercial@');
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(ScanSoloAiAgentConfigAPI.updateDraft).not.toHaveBeenCalled();
    });

    it('leaves the ScanSolo menu items unchanged', () => {
      const items = buildScanSoloSidebarItems({
        t: key => key,
        accountScopedRoute: name => name,
      });

      expect(items).toEqual([
        {
          name: 'ScanSolo pipeline',
          label: 'SCANSOLO.SIDEBAR.PIPELINE',
          icon: 'i-lucide-kanban-square',
          to: 'scansolo_pipeline_index',
          activeOn: ['scansolo_pipeline_index'],
        },
        {
          name: 'ScanSolo agent',
          label: 'SCANSOLO.SIDEBAR.AGENT',
          icon: 'i-lucide-bot',
          to: 'scansolo_agent_index',
          activeOn: ['scansolo_agent_index'],
        },
        {
          name: 'ScanSolo knowledge',
          label: 'SCANSOLO.SIDEBAR.KNOWLEDGE',
          icon: 'i-lucide-book-open',
          to: 'scansolo_knowledge_index',
          activeOn: ['scansolo_knowledge_index'],
        },
        {
          name: 'ScanSolo followups',
          label: 'SCANSOLO.SIDEBAR.FOLLOWUPS',
          icon: 'i-lucide-repeat-2',
          to: 'scansolo_followups_index',
          activeOn: ['scansolo_followups_index'],
        },
        {
          name: 'ScanSolo proposals',
          label: 'SCANSOLO.SIDEBAR.PROPOSALS',
          icon: 'i-lucide-file-text',
          to: 'scansolo_proposals_index',
          activeOn: ['scansolo_proposals_index'],
        },
        {
          name: 'ScanSolo executions',
          label: 'SCANSOLO.SIDEBAR.EXECUTIONS',
          icon: 'i-lucide-shield-check',
          to: 'scansolo_executions_index',
          activeOn: ['scansolo_executions_index'],
        },
      ]);
    });
  });
});
