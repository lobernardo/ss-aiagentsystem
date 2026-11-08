import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import ScanSoloPipelineOpportunitiesAPI from 'dashboard/api/scansoloPipelineOpportunities';
import MarkHandledManuallyButton from '../MarkHandledManuallyButton.vue';

vi.mock('dashboard/api/scansoloPipelineOpportunities', () => ({
  default: { markHandledManually: vi.fn() },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

withFullI18n();
enableAutoUnmount(afterEach);

const eligible = {
  id: 7,
  stage: 'qualificado',
  commercialStatus: 'aguardando_artur',
};

const mountButton = (opportunity = eligible) =>
  mount(MarkHandledManuallyButton, { props: { opportunity } });

const button = wrapper =>
  wrapper.find('[data-testid="mark-handled-manually-button"]');

const openAndConfirm = async wrapper => {
  await button(wrapper).trigger('click');
  await wrapper.find('[data-testid="confirm-dialog-confirm"]').trigger('click');
  await flushPromises();
};

describe('MarkHandledManuallyButton', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
  });

  describe('visibility', () => {
    it.each([
      ['qualificado', 'aguardando_artur', true],
      ['proposta_enviada', 'aguardando_artur', true],
      ['em_qualificacao', 'aguardando_artur', false],
      ['negociacao', 'aguardando_artur', false],
      ['qualificado', 'nao_encaminhado', false],
      ['qualificado', 'resposta_recebida', false],
      ['proposta_enviada', 'proposta_enviada_manual', false],
    ])('%s + %s → %s', (stage, commercialStatus, visible) => {
      const wrapper = mountButton({ id: 7, stage, commercialStatus });

      expect(button(wrapper).exists()).toBe(visible);
    });
  });

  it('opens a confirmation saying nothing is sent and the cadence follows', async () => {
    const wrapper = mountButton();

    expect(button(wrapper).text()).toBe('Marcar proposta enviada manualmente');
    expect(wrapper.find('[data-testid="confirm-dialog"]').exists()).toBe(false);

    await button(wrapper).trigger('click');

    expect(wrapper.find('[data-testid="confirm-dialog-message"]').text()).toBe(
      'Nenhuma mensagem será enviada agora. A cadência pós-proposta existente seguirá normalmente.'
    );
  });

  it('does not call the API when cancelled', async () => {
    const wrapper = mountButton();

    await button(wrapper).trigger('click');
    await wrapper
      .find('[data-testid="confirm-dialog-cancel"]')
      .trigger('click');
    await flushPromises();

    expect(
      ScanSoloPipelineOpportunitiesAPI.markHandledManually
    ).not.toHaveBeenCalled();
    expect(wrapper.find('[data-testid="confirm-dialog"]').exists()).toBe(false);
  });

  it('calls CT-03 on confirm and emits the updated opportunity', async () => {
    ScanSoloPipelineOpportunitiesAPI.markHandledManually.mockResolvedValue({
      data: {
        id: 7,
        stage: 'proposta_enviada',
        commercial_status: 'proposta_enviada_manual',
      },
    });
    const wrapper = mountButton();

    await openAndConfirm(wrapper);

    expect(
      ScanSoloPipelineOpportunitiesAPI.markHandledManually
    ).toHaveBeenCalledWith(7);
    expect(wrapper.emitted('updated')[0][0]).toEqual({
      id: 7,
      stage: 'proposta_enviada',
      commercialStatus: 'proposta_enviada_manual',
    });
    expect(useAlert).toHaveBeenCalledWith(
      'Proposta marcada como enviada manualmente.'
    );
  });

  it('shows the i18n message of a 422 quote_request_closed', async () => {
    ScanSoloPipelineOpportunitiesAPI.markHandledManually.mockRejectedValue({
      response: { status: 422, data: { error: 'quote_request_closed' } },
    });
    const wrapper = mountButton();

    await openAndConfirm(wrapper);

    expect(useAlert).toHaveBeenCalledWith(
      'O pedido de orçamento desta oportunidade já foi encerrado.'
    );
    expect(wrapper.emitted('updated')).toBeUndefined();
  });
});
