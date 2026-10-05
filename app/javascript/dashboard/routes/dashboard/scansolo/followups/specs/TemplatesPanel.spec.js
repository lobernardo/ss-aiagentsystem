import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import ScanSoloCadenceTemplatesAPI from 'dashboard/api/scansoloCadenceTemplates';
import TemplatesPanel from '../TemplatesPanel.vue';

vi.mock('dashboard/api/scansoloCadenceTemplates', () => ({
  default: { get: vi.fn(), update: vi.fn() },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

withFullI18n();
enableAutoUnmount(afterEach);

const availableRow = {
  stage: 'novo_lead',
  step: 1,
  template_name: 'scansolo_novo_lead_1',
  language: 'pt_BR',
  params: [{ source: 'contact_first_name' }],
  mapped: true,
  availability: 'available',
  block_reason: null,
  meta_status: 'APPROVED',
  last_synced_at: '2026-01-05T12:00:00Z',
};

const pausedRow = {
  stage: 'proposta_enviada',
  step: null,
  template_name: 'scansolo_proposal_send',
  language: 'pt_BR',
  params: [],
  mapped: false,
  availability: 'blocked',
  block_reason: 'template_paused',
  meta_status: 'PAUSED',
  last_synced_at: null,
};

const mountPanel = ({ role = 'administrator' } = {}) =>
  mount(TemplatesPanel, {
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

const row = (wrapper, key) =>
  wrapper.find(`[data-testid="template-row"][data-row-key="${key}"]`);

describe('TemplatesPanel', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    ScanSoloCadenceTemplatesAPI.get.mockResolvedValue({
      data: [availableRow, pausedRow],
    });
  });

  it('renders an available and a paused template with availability, Meta status and reason (UI-12)', async () => {
    const wrapper = mountPanel();
    await flushPromises();

    const available = row(wrapper, 'novo_lead:1');
    expect(available.text()).toContain('Novo Lead · Tentativa 1');
    expect(available.find('[data-testid="template-name"]').text()).toBe(
      'scansolo_novo_lead_1'
    );
    expect(available.find('[data-testid="template-language"]').text()).toBe(
      'pt_BR'
    );
    expect(available.find('[data-testid="template-params"]').text()).toBe(
      'Primeiro nome do contato'
    );
    expect(available.find('[data-testid="template-availability"]').text()).toBe(
      'Disponível'
    );
    expect(available.find('[data-testid="template-meta-status"]').text()).toBe(
      'Aprovado'
    );
    expect(
      available.find('[data-testid="template-block-reason"]').exists()
    ).toBe(false);
    expect(
      available.find('[data-testid="template-last-sync"]').attributes('title')
    ).toBe('05/01/2026 12:00');

    const paused = row(wrapper, 'proposta_enviada:proposal');
    expect(paused.text()).toContain('Envio de proposta');
    expect(paused.find('[data-testid="template-availability"]').text()).toBe(
      'Bloqueado'
    );
    expect(paused.find('[data-testid="template-meta-status"]').text()).toBe(
      'Pausado'
    );
    expect(
      paused.find('[data-testid="template-block-reason"]').text()
    ).toContain('Modelo pausado pela Meta');
    expect(paused.text()).toContain('Nunca sincronizado');
    expect(paused.text()).toContain('Nome padrão (sem mapeamento)');
    expect(wrapper.html()).not.toContain('2026-01-05T');
  });

  it('shows no edit control to agents', async () => {
    const wrapper = mountPanel({ role: 'agent' });
    await flushPromises();

    expect(wrapper.findAll('[data-testid="template-row"]')).toHaveLength(2);
    expect(wrapper.find('[data-testid="template-edit-button"]').exists()).toBe(
      false
    );
  });

  it('lets an administrator edit a mapping through PUT and shows the updated row', async () => {
    ScanSoloCadenceTemplatesAPI.update.mockResolvedValue({
      data: {
        ...pausedRow,
        template_name: 'proposta_v2',
        params: [{ source: 'static', value: 'Oi' }],
        mapped: true,
        availability: 'available',
        block_reason: null,
        meta_status: 'APPROVED',
      },
    });
    const wrapper = mountPanel();
    await flushPromises();
    const paused = row(wrapper, 'proposta_enviada:proposal');

    await paused.find('[data-testid="template-edit-button"]').trigger('click');
    await paused
      .find('[data-testid="template-edit-name"]')
      .setValue('proposta_v2');
    await paused.find('[data-testid="template-add-param"]').trigger('click');
    const param = paused.find('[data-testid="template-edit-param"]');
    await param.find('select').setValue('static');
    await param.find('input').setValue('Oi');
    await paused.find('[data-testid="template-edit-form"]').trigger('submit');
    await flushPromises();

    expect(ScanSoloCadenceTemplatesAPI.update).toHaveBeenCalledWith({
      stage: 'proposta_enviada',
      step: null,
      template_name: 'proposta_v2',
      language: 'pt_BR',
      params: [{ source: 'static', value: 'Oi' }],
    });
    const updated = row(wrapper, 'proposta_enviada:proposal');
    expect(updated.find('[data-testid="template-availability"]').text()).toBe(
      'Disponível'
    );
    expect(updated.find('[data-testid="template-edit-form"]').exists()).toBe(
      false
    );
    expect(useAlert).toHaveBeenCalledWith('Modelo atualizado.');
  });

  it('toasts the 422 details returned by the server', async () => {
    ScanSoloCadenceTemplatesAPI.update.mockRejectedValue({
      response: {
        status: 422,
        data: {
          error: 'invalid_template_mapping',
          details: ['param source "phone" is not allowed'],
        },
      },
    });
    const wrapper = mountPanel();
    await flushPromises();
    const available = row(wrapper, 'novo_lead:1');

    await available
      .find('[data-testid="template-edit-button"]')
      .trigger('click');
    await available
      .find('[data-testid="template-edit-form"]')
      .trigger('submit');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'param source "phone" is not allowed'
    );
    expect(available.find('[data-testid="template-edit-form"]').exists()).toBe(
      true
    );
  });

  it('renders the loading and error states', async () => {
    ScanSoloCadenceTemplatesAPI.get.mockReturnValueOnce(new Promise(() => {}));
    const loading = mountPanel();
    await flushPromises();
    expect(loading.find('[data-testid="list-state-loading"]').exists()).toBe(
      true
    );

    ScanSoloCadenceTemplatesAPI.get.mockRejectedValueOnce(new Error('boom'));
    const failed = mountPanel();
    await flushPromises();
    expect(failed.find('[data-testid="list-state-error"]').exists()).toBe(true);
  });

  it('labels the lead_manual_inicial and proposta_acompanhamento slot rows (CT-09)', async () => {
    const slotRow = stage => ({
      ...pausedRow,
      stage,
      template_name: `scansolo_${stage}`,
      availability: 'available',
      block_reason: null,
      meta_status: 'APPROVED',
    });
    ScanSoloCadenceTemplatesAPI.get.mockResolvedValue({
      data: [
        availableRow,
        slotRow('lead_manual_inicial'),
        slotRow('proposta_acompanhamento'),
      ],
    });
    const wrapper = mountPanel();
    await flushPromises();

    expect(
      row(wrapper, 'lead_manual_inicial:proposal')
        .find('[data-testid="template-title"]')
        .text()
    ).toBe('Mensagem inicial do lead manual');
    expect(
      row(wrapper, 'proposta_acompanhamento:proposal')
        .find('[data-testid="template-title"]')
        .text()
    ).toBe('Acompanhamento da proposta');
    expect(wrapper.text()).not.toContain('lead_manual_inicial ·');
  });
});
