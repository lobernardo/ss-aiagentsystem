import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import ScanSoloPipelineOpportunitiesAPI from 'dashboard/api/scansoloPipelineOpportunities';
import ScanSoloAiAgentConfigAPI from 'dashboard/api/scansoloAiAgentConfig';
import { useScansoloPipelineOpportunitiesStore } from 'dashboard/store/scansolo/pipelineOpportunities';
import NewLeadDialog from '../NewLeadDialog.vue';

vi.mock('dashboard/api/scansoloPipelineOpportunities', () => ({
  default: { create: vi.fn() },
}));

vi.mock('dashboard/api/scansoloAiAgentConfig', () => ({
  default: { get: vi.fn() },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const push = vi.fn();
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1 } }),
  useRouter: () => ({ push }),
}));

withFullI18n();
enableAutoUnmount(afterEach);

const openDialog = vi.fn();
const closeDialog = vi.fn();
const DialogStub = {
  name: 'Dialog',
  emits: ['confirm', 'close'],
  methods: { open: openDialog, close: closeDialog },
  template: `
    <section>
      <slot />
      <button data-testid="dialog-confirm" @click="$emit('confirm')" />
    </section>
  `,
};

const WHATSAPP = {
  id: 11,
  name: 'WhatsApp Vendas',
  channel_type: 'Channel::Whatsapp',
};
const OTHER_WHATSAPP = {
  id: 12,
  name: 'WhatsApp Suporte',
  channel_type: 'Channel::Whatsapp',
};
const EMAIL = { id: 13, name: 'Comercial', channel_type: 'Channel::Email' };

const createdOpportunity = {
  id: 30,
  contact_name: 'João Comercial',
  stage: 'novo_lead',
  lead_source: 'manual',
};

const mockPublishedAllowlist = allowedInboxIds =>
  ScanSoloAiAgentConfigAPI.get.mockResolvedValue({
    data: {
      draft: null,
      published: { allowed_inbox_ids: allowedInboxIds },
      available_models: [],
    },
  });

const mountDialog = async ({
  inboxes = [WHATSAPP, OTHER_WHATSAPP, EMAIL],
} = {}) => {
  const wrapper = mount(NewLeadDialog, {
    global: {
      plugins: [
        createStore({
          getters: {
            'agents/getAgents': () => [{ id: 42, name: 'Carla Vendas' }],
            'inboxes/getInboxes': () => inboxes,
          },
        }),
      ],
      stubs: { Dialog: DialogStub },
    },
  });
  await wrapper.vm.open();
  await flushPromises();
  return wrapper;
};

const fill = async (wrapper, { name = 'João Comercial', phone = '' } = {}) => {
  await wrapper.find('input[data-testid="new-lead-name"]').setValue(name);
  await wrapper.find('input[data-testid="new-lead-phone"]').setValue(phone);
};

const confirm = async wrapper => {
  await wrapper.find('[data-testid="dialog-confirm"]').trigger('click');
  await flushPromises();
};

const reject422 = data =>
  ScanSoloPipelineOpportunitiesAPI.create.mockRejectedValue({
    response: { status: 422, data },
  });

describe('NewLeadDialog', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    mockPublishedAllowlist([11]);
  });

  it('shows the phone error and sends 0 requests without a phone', async () => {
    const wrapper = await mountDialog();
    await fill(wrapper, { phone: '' });

    await confirm(wrapper);

    expect(ScanSoloPipelineOpportunitiesAPI.create).not.toHaveBeenCalled();
    expect(wrapper.text()).toContain(
      'Informe o telefone no formato E.164, por exemplo +5511999999999.'
    );
  });

  it('rejects a phone outside E.164 locally', async () => {
    const wrapper = await mountDialog();
    await fill(wrapper, { phone: '11 99999-9999' });

    await confirm(wrapper);

    expect(ScanSoloPipelineOpportunitiesAPI.create).not.toHaveBeenCalled();
  });

  it('pre-selects the only allowlisted WhatsApp inbox and sends it', async () => {
    ScanSoloPipelineOpportunitiesAPI.create.mockResolvedValue({
      data: createdOpportunity,
    });
    const wrapper = await mountDialog();

    const inboxSelect = wrapper.find('[data-testid="new-lead-inbox"]');
    expect(inboxSelect.element.value).toBe('11');
    expect(
      inboxSelect.findAll('option:not([disabled])').map(o => o.text())
    ).toEqual(['WhatsApp Vendas']);

    await fill(wrapper, { phone: '+5511999999999' });
    await confirm(wrapper);

    expect(ScanSoloPipelineOpportunitiesAPI.create).toHaveBeenCalledWith({
      name: 'João Comercial',
      phone_number: '+5511999999999',
      email: undefined,
      company: undefined,
      owner_id: undefined,
      initial_stage: 'novo_lead',
      inbox_id: 11,
    });
  });

  it('places the initial stage between owner and inbox, defaulting to Novo Lead', async () => {
    const wrapper = await mountDialog();

    const selects = wrapper
      .findAll('select')
      .map(select => select.attributes('data-testid'));
    expect(selects).toEqual([
      'new-lead-owner',
      'new-lead-initial-stage',
      'new-lead-inbox',
    ]);
    expect(wrapper.text()).toContain('Etapa inicial do pipeline');
    const stageSelect = wrapper.find('[data-testid="new-lead-initial-stage"]');
    expect(stageSelect.element.value).toBe('novo_lead');
    expect(
      stageSelect.findAll('option:not([disabled])').map(o => o.text())
    ).toEqual([
      'Novo Lead',
      'Em Contato',
      'Em Qualificação',
      'Qualificado',
      'Perdido',
    ]);
  });

  it('disables Proposta Enviada and Negociação with the reason', async () => {
    const wrapper = await mountDialog();

    const disabled = wrapper
      .findAll('[data-testid="new-lead-initial-stage"] option[disabled]')
      .map(o => [o.attributes('value'), o.text()]);
    expect(disabled).toEqual([
      [
        'proposta_enviada',
        'Proposta Enviada (indisponível: exige uma proposta real enviada)',
      ],
      [
        'negociacao',
        'Negociação (indisponível: exige uma proposta real enviada)',
      ],
    ]);
    expect(
      wrapper.find('[data-testid="new-lead-initial-stage-hint"]').text()
    ).toContain('Proposta Enviada e Negociação');
  });

  it('sends the chosen initial stage', async () => {
    ScanSoloPipelineOpportunitiesAPI.create.mockResolvedValue({
      data: { ...createdOpportunity, stage: 'em_qualificacao' },
    });
    const wrapper = await mountDialog();
    await fill(wrapper, { phone: '+5511999999999' });
    await wrapper
      .find('[data-testid="new-lead-initial-stage"]')
      .setValue('em_qualificacao');

    await confirm(wrapper);

    expect(ScanSoloPipelineOpportunitiesAPI.create).toHaveBeenCalledWith(
      expect.objectContaining({ initial_stage: 'em_qualificacao' })
    );
  });

  it('shows the i18n message of a 422 invalid_initial_stage', async () => {
    reject422({ error: 'invalid_initial_stage' });
    const wrapper = await mountDialog();
    await fill(wrapper, { phone: '+5511999999999' });

    await confirm(wrapper);

    expect(
      wrapper.find('[data-testid="new-lead-server-error"]').text()
    ).toContain('Esta etapa não pode receber um lead novo.');
  });

  it('requires an inbox when more than one WhatsApp inbox is allowlisted', async () => {
    mockPublishedAllowlist([11, 12]);
    const wrapper = await mountDialog();

    expect(wrapper.find('[data-testid="new-lead-inbox"]').element.value).toBe(
      ''
    );
    await fill(wrapper, { phone: '+5511999999999' });
    await confirm(wrapper);

    expect(ScanSoloPipelineOpportunitiesAPI.create).not.toHaveBeenCalled();
    expect(wrapper.find('[data-testid="new-lead-inbox-error"]').text()).toBe(
      'Escolha uma caixa de entrada WhatsApp atendida pela IA.'
    );
  });

  it('shows the i18n message of a 422 contact_conflict', async () => {
    reject422({ error: 'contact_conflict' });
    const wrapper = await mountDialog();
    await fill(wrapper, { phone: '+5511999999999' });

    await confirm(wrapper);

    expect(
      wrapper.find('[data-testid="new-lead-server-error"]').text()
    ).toContain(
      'O telefone e o e-mail informados pertencem a contatos diferentes.'
    );
    expect(
      wrapper.find('[data-testid="new-lead-open-existing"]').exists()
    ).toBe(false);
    expect(closeDialog).not.toHaveBeenCalled();
  });

  it('offers to open the existing opportunity on 422 opportunity_exists', async () => {
    reject422({ error: 'opportunity_exists', opportunity_id: 7 });
    const wrapper = await mountDialog();
    await fill(wrapper, { phone: '+5511999999999' });
    await confirm(wrapper);

    expect(
      wrapper.find('[data-testid="new-lead-server-error"]').text()
    ).toContain('Este contato já tem uma oportunidade em andamento.');
    await wrapper
      .find('[data-testid="new-lead-open-existing"]')
      .trigger('click');

    expect(push).toHaveBeenCalledWith({
      name: 'scansolo_pipeline_opportunity_detail',
      params: { accountId: 1, opportunityId: 7 },
    });
  });

  it('closes and adds the card to the store on 201', async () => {
    ScanSoloPipelineOpportunitiesAPI.create.mockResolvedValue({
      data: createdOpportunity,
    });
    const wrapper = await mountDialog();
    await fill(wrapper, { phone: '+5511999999999' });

    await confirm(wrapper);

    expect(closeDialog).toHaveBeenCalled();
    expect(useAlert).toHaveBeenCalledWith('Lead cadastrado.');
    expect(useScansoloPipelineOpportunitiesStore().opportunities).toEqual([
      {
        id: 30,
        contactName: 'João Comercial',
        stage: 'novo_lead',
        leadSource: 'manual',
      },
    ]);
  });

  it('emits close when the dialog closes', async () => {
    const wrapper = await mountDialog();

    wrapper.findComponent(DialogStub).vm.$emit('close');

    expect(wrapper.emitted('close')).toHaveLength(1);
  });
});
