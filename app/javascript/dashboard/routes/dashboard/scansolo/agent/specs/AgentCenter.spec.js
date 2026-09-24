import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import { onBeforeRouteLeave } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import ScanSoloAiAgentConfigAPI from 'dashboard/api/scansoloAiAgentConfig';
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
  updated_at: '2026-01-01T09:00:00Z',
};

const inboxesFixture = [
  { id: 11, name: 'WhatsApp Vendas' },
  { id: 12, name: 'WhatsApp Suporte' },
];

const AVAILABLE_MODELS = ['gpt-4.1-mini', 'gpt-4.1', 'gpt-5.1', 'gpt-5.2'];

const mountAgentCenter = ({ role = 'administrator' } = {}) =>
  mount(AgentCenter, {
    global: {
      plugins: [
        createStore({
          getters: {
            'inboxes/getInboxes': () => inboxesFixture,
            getCurrentRole: () => role,
            getCurrentUser: () => ({ id: 5 }),
          },
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
      'Proposta',
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

    expect(ScanSoloAiAgentConfigAPI.updateDraft).toHaveBeenCalledWith(
      expect.objectContaining({
        allowed_inbox_ids: [12, 11],
        require_proposal_approval: true,
      })
    );
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

  describe('UI-07 / UI-08: approval toggle and model selects', () => {
    it('persists the require_proposal_approval toggle from the Proposta section', async () => {
      ScanSoloAiAgentConfigAPI.updateDraft.mockResolvedValue({
        data: { ...draftFixture, require_proposal_approval: false },
      });
      const wrapper = mountAgentCenter();
      await flushPromises();
      const toggle = wrapper.find(
        '[data-testid="section-proposal"] [data-testid="field-requireProposalApproval"]'
      );

      await toggle.setValue(false);
      await wrapper.find('form').trigger('submit');
      await flushPromises();

      expect(ScanSoloAiAgentConfigAPI.updateDraft).toHaveBeenCalledWith(
        expect.objectContaining({ require_proposal_approval: false })
      );
      expect(toggle.element.checked).toBe(false);
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
});
