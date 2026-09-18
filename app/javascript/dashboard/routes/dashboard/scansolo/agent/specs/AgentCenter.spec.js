import { mount, flushPromises } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import ScanSoloAiAgentConfigAPI from 'dashboard/api/scansoloAiAgentConfig';
import AgentCenter from '../AgentCenter.vue';

vi.mock('dashboard/api/scansoloAiAgentConfig', () => ({
  default: {
    get: vi.fn(),
    updateDraft: vi.fn(),
    publish: vi.fn(),
  },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

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
  updated_at: '2026-01-01T09:00:00Z',
};

describe('AgentCenter', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    ScanSoloAiAgentConfigAPI.get.mockResolvedValue({
      data: { draft: draftFixture, published: null },
    });
  });

  it('exposes every RF-20 field', async () => {
    const wrapper = mount(AgentCenter);
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

  it('shows a visible draft-vs-published indicator', async () => {
    const wrapper = mount(AgentCenter);
    await flushPromises();

    expect(wrapper.find('[data-testid="agent-status-indicator"]').text()).toBe(
      'SCANSOLO.AGENT_CENTER.STATUS_NOT_PUBLISHED'
    );

    ScanSoloAiAgentConfigAPI.get.mockResolvedValue({
      data: {
        draft: draftFixture,
        published: { ...draftFixture, status: 'published' },
      },
    });
    const publishedWrapper = mount(AgentCenter);
    await flushPromises();

    expect(
      publishedWrapper.find('[data-testid="agent-status-indicator"]').text()
    ).toBe('SCANSOLO.AGENT_CENTER.STATUS_PUBLISHED');
  });

  it('blocks accidental publish: clicking Publish only opens a confirmation, it does not call the API', async () => {
    const wrapper = mount(AgentCenter);
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

    const wrapper = mount(AgentCenter);
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
    const wrapper = mount(AgentCenter);
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

    const wrapper = mount(AgentCenter);
    await flushPromises();

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(ScanSoloAiAgentConfigAPI.updateDraft).toHaveBeenCalledTimes(1);
    expect(ScanSoloAiAgentConfigAPI.publish).not.toHaveBeenCalled();
  });
});
