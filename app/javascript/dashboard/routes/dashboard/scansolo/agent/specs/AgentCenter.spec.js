import { mount, flushPromises } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import ScanSoloAiAgentConfigAPI from 'dashboard/api/scansoloAiAgentConfig';
import AgentCenter from '../AgentCenter.vue';

vi.mock('dashboard/api/scansoloAiAgentConfig', () => ({
  default: {
    get: vi.fn(),
    updateDraft: vi.fn(),
    publish: vi.fn(),
  },
}));

withFullI18n();

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
  updated_at: '2026-01-01T09:00:00Z',
};

const inboxesFixture = [
  { id: 11, name: 'WhatsApp Vendas' },
  { id: 12, name: 'WhatsApp Suporte' },
];

const mountAgentCenter = () =>
  mount(AgentCenter, {
    global: {
      plugins: [
        createStore({
          getters: { 'inboxes/getInboxes': () => inboxesFixture },
        }),
      ],
    },
  });

describe('AgentCenter', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    ScanSoloAiAgentConfigAPI.get.mockResolvedValue({
      data: { draft: draftFixture, published: null },
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
});
