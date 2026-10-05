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
      inbox_id: 11,
    });
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
