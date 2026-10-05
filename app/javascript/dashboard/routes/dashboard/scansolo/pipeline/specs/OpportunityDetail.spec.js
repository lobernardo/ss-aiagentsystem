import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import ScanSoloPipelineOpportunitiesAPI from 'dashboard/api/scansoloPipelineOpportunities';
import OpportunityDetail from '../OpportunityDetail.vue';

vi.mock('dashboard/api/scansoloPipelineOpportunities', () => ({
  default: {
    show: vi.fn(),
    resendQuoteRequest: vi.fn(),
  },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const push = vi.fn();
vi.mock('vue-router', () => ({
  useRoute: () => ({
    params: { accountId: 1, opportunityId: 7 },
  }),
  useRouter: () => ({ push }),
}));

withFullI18n();
enableAutoUnmount(afterEach);

const ISO_PATTERN = /\d{4}-\d{2}-\d{2}T/;

const seededOpportunity = {
  id: 7,
  account_id: 1,
  contact_id: 3,
  contact_name: 'Ada Lovelace',
  conversation_id: 9,
  owner_id: 42,
  stage: 'em_qualificacao',
  last_customer_interaction_at: '2026-01-01T10:00:00Z',
  next_follow_up_at: null,
  stage_history: [
    {
      id: 1,
      from_stage: 'novo_lead',
      to_stage: 'em_contato',
      actor_type: null,
      actor_id: null,
      created_at: '2026-01-01T08:00:00Z',
    },
    {
      id: 2,
      from_stage: 'em_contato',
      to_stage: 'em_qualificacao',
      actor_type: 'User',
      actor_id: 5,
      created_at: '2026-01-01T09:00:00Z',
    },
  ],
};

const mountDetail = ({ role = 'administrator' } = {}) =>
  mount(OpportunityDetail, {
    global: {
      plugins: [
        createStore({
          getters: {
            getCurrentRole: () => role,
            getCurrentUser: () => ({ id: 1 }),
            'agents/getAgents': () => [{ id: 42, name: 'Carla Vendas' }],
          },
          actions: { 'agents/get': vi.fn() },
        }),
      ],
    },
  });

describe('OpportunityDetail', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    ScanSoloPipelineOpportunitiesAPI.show.mockResolvedValue({
      data: seededOpportunity,
    });
  });

  it('shows a chronological stage-history list matching the seeded PipelineStageEvent records', async () => {
    const wrapper = mountDetail();
    await flushPromises();

    expect(ScanSoloPipelineOpportunitiesAPI.show).toHaveBeenCalledWith(7);
    const items = wrapper.findAll('[data-testid="opportunity-history-item"]');
    expect(items).toHaveLength(2);
    expect(items[0].find('[data-testid="history-from-stage"]').text()).toBe(
      'Novo Lead'
    );
    expect(items[0].find('[data-testid="history-to-stage"]').text()).toBe(
      'Em Contato'
    );
    expect(items[1].find('[data-testid="history-from-stage"]').text()).toBe(
      'Em Contato'
    );
    expect(items[1].find('[data-testid="history-to-stage"]').text()).toBe(
      'Em Qualificação'
    );
    expect(
      items[0].find('[data-testid="history-created-at"]').attributes('title')
    ).toBe('01/01/2026 08:00');
  });

  it('shows the related contact and navigates to the related conversation', async () => {
    const wrapper = mountDetail();
    await flushPromises();

    expect(
      wrapper.find('[data-testid="opportunity-contact-name"]').text()
    ).toBe('Ada Lovelace');
    expect(wrapper.find('[data-testid="opportunity-stage"]').text()).toContain(
      'Em Qualificação'
    );

    await wrapper
      .find('[data-testid="opportunity-conversation-link"]')
      .trigger('click');

    expect(push).toHaveBeenCalledWith({
      name: 'inbox_conversation',
      params: { accountId: 1, conversation_id: 9 },
    });
  });

  it('shows an empty state when no stage history exists yet', async () => {
    ScanSoloPipelineOpportunitiesAPI.show.mockResolvedValue({
      data: { ...seededOpportunity, stage_history: [] },
    });

    const wrapper = mountDetail();
    await flushPromises();

    expect(
      wrapper.find('[data-testid="opportunity-history-empty"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="opportunity-history-list"]').exists()
    ).toBe(false);
  });

  it('hides owner id and ISO timestamps from agents and shows them to admins collapsed', async () => {
    const agentView = mountDetail({ role: 'agent' });
    await flushPromises();
    expect(agentView.html()).not.toMatch(ISO_PATTERN);
    expect(agentView.find('[data-testid="technical-details"]').exists()).toBe(
      false
    );

    const adminView = mountDetail();
    await flushPromises();
    const details = adminView.find('[data-testid="technical-details"]');
    expect(details.attributes('open')).toBeUndefined();
    expect(details.text()).toContain('42');
    expect(details.text()).toMatch(ISO_PATTERN);
  });

  it('renders the loading and error states (UI-09)', async () => {
    ScanSoloPipelineOpportunitiesAPI.show.mockReturnValueOnce(
      new Promise(() => {})
    );
    const loading = mountDetail();
    await flushPromises();
    expect(loading.find('[data-testid="list-state-loading"]').exists()).toBe(
      true
    );

    ScanSoloPipelineOpportunitiesAPI.show.mockRejectedValueOnce(
      new Error('boom')
    );
    const failed = mountDetail();
    await flushPromises();
    expect(failed.find('[data-testid="list-state-error"]').exists()).toBe(true);
  });

  describe('UI-04 / UI-07: lead screen', () => {
    const field = (key, label, value, status) => ({
      key,
      label,
      value,
      status,
      classification: 'obrigatorio',
    });

    const leadShow = {
      ...seededOpportunity,
      lead_source: 'manual',
      company: 'Solar Ltda',
      service: 'Georradar',
      city_uf: null,
      ai_control_state: 'ai_active',
      quote_request_status: 'replied',
      proposal_status: 'generated',
      lead_state: {
        blocks: {
          identificacao: [
            field('nome', 'Contato', 'Ada Lovelace', 'confirmado'),
            field(
              'empresa',
              'Empresa / razão social',
              'Solar Ltda',
              'inferido'
            ),
          ],
          servico: [
            field('tipo_servico', 'Tipo de serviço', 'Georradar', 'confirmado'),
            field('tecnologia', 'Tecnologia', null, 'faltante'),
          ],
          local: [field('cidade_uf', 'Cidade / UF', null, 'faltante')],
        },
      },
      quote_request: {
        id: 3,
        status: 'replied',
        sent_at: '2026-01-02T10:00:00Z',
        replied_at: '2026-01-03T15:30:00Z',
        email_conversation_id: 77,
      },
      proposal: {
        version_number: 2,
        proposal_number: 'SS-2026-0042',
        status: 'generated',
        value: '15000.0',
        currency: 'BRL',
        valid_until: '2026-02-15',
        document_url: 'https://chat.test/rails/active_storage/proposal.pdf',
        failure_reason: null,
      },
      initial_template_failure: null,
      quote_request_resend_available: false,
    };

    const mountShow = async (overrides = {}, options = {}) => {
      ScanSoloPipelineOpportunitiesAPI.show.mockResolvedValue({
        data: { ...leadShow, ...overrides },
      });
      const wrapper = mountDetail(options);
      await flushPromises();
      return wrapper;
    };

    const sectionKeys = (wrapper, status) =>
      wrapper
        .findAll(
          `[data-testid="qualification-${status}"] [data-testid="qualification-field"]`
        )
        .map(item => item.attributes('data-field-key'));

    it('groups the lead-state fields into Coletado, A confirmar and Faltante (RF-45)', async () => {
      const wrapper = await mountShow();

      expect(sectionKeys(wrapper, 'confirmado')).toEqual([
        'nome',
        'tipo_servico',
      ]);
      expect(sectionKeys(wrapper, 'inferido')).toEqual(['empresa']);
      expect(sectionKeys(wrapper, 'faltante')).toEqual([
        'tecnologia',
        'cidade_uf',
      ]);
      expect(
        wrapper.find('[data-testid="qualification-confirmado"] h4').text()
      ).toBe('Coletado');
      expect(
        wrapper.find('[data-testid="qualification-inferido"] h4').text()
      ).toBe('A confirmar');
      expect(
        wrapper.find('[data-testid="qualification-faltante"] h4').text()
      ).toBe('Faltante');
      expect(
        wrapper.find('[data-testid="qualification-confirmado"]').text()
      ).toContain('Tipo de serviço: Georradar');
    });

    it('shows origin, owner, quote request and the generated proposal with value and validity', async () => {
      const wrapper = await mountShow();

      expect(
        wrapper.find('[data-testid="opportunity-lead-source"]').text()
      ).toBe('Origem: Comercial');
      expect(wrapper.find('[data-testid="opportunity-owner"]').text()).toBe(
        'Responsável: Carla Vendas'
      );
      expect(wrapper.find('[data-testid="quote-request-status"]').text()).toBe(
        'Status do orçamento: Orçamento recebido'
      );
      expect(
        wrapper
          .find('[data-testid="quote-request-sent-at"]')
          .attributes('title')
      ).toBe('02/01/2026 10:00');
      expect(
        wrapper
          .find('[data-testid="quote-request-replied-at"]')
          .attributes('title')
      ).toBe('03/01/2026 15:30');
      expect(wrapper.find('[data-testid="proposal-version"]').text()).toBe(
        'Versão: 2'
      );
      expect(wrapper.find('[data-testid="proposal-number"]').text()).toBe(
        'Número: SS-2026-0042'
      );
      expect(wrapper.find('[data-testid="proposal-status"]').text()).toBe(
        'Status da proposta: Gerada'
      );
      expect(wrapper.find('[data-testid="proposal-value"]').text()).toMatch(
        /^Valor: R\$\s15\.000,00$/
      );
      expect(wrapper.find('[data-testid="proposal-valid-until"]').text()).toBe(
        'Validade: 15/02/2026'
      );
      expect(
        wrapper
          .find('[data-testid="proposal-document-link"]')
          .attributes('href')
      ).toBe(leadShow.proposal.document_url);
    });

    it('reads "Não informada" for an empty origin and hides value/validity while generating', async () => {
      const wrapper = await mountShow({
        lead_source: null,
        proposal: { ...leadShow.proposal, status: 'generating' },
      });

      expect(
        wrapper.find('[data-testid="opportunity-lead-source"]').text()
      ).toBe('Origem: Não informada');
      expect(wrapper.find('[data-testid="proposal-value"]').exists()).toBe(
        false
      );
      expect(
        wrapper.find('[data-testid="proposal-valid-until"]').exists()
      ).toBe(false);
    });

    it('shows the empty quote and proposal states', async () => {
      const wrapper = await mountShow({ quote_request: null, proposal: null });

      expect(wrapper.find('[data-testid="quote-request-none"]').text()).toBe(
        'Nenhuma solicitação de orçamento.'
      );
      expect(wrapper.find('[data-testid="proposal-none"]').text()).toBe(
        'Nenhuma proposta gerada.'
      );
    });

    it('shows the initial template failure reason and status, and hides it when null (RF-08)', async () => {
      const failed = await mountShow({
        initial_template_failure: {
          reason: 'template_paused',
          status: 'blocked',
          occurred_at: '2026-01-01T08:00:00Z',
        },
      });

      expect(
        failed.find('[data-testid="initial-template-failure-reason"]').text()
      ).toBe('Motivo: Modelo pausado pela Meta');
      expect(
        failed.find('[data-testid="initial-template-failure-status"]').text()
      ).toBe('Status: Bloqueada');

      const clean = await mountShow();
      expect(
        clean.find('[data-testid="initial-template-failure"]').exists()
      ).toBe(false);
    });

    it('lets an administrator resend the quote request and reloads the show', async () => {
      ScanSoloPipelineOpportunitiesAPI.resendQuoteRequest.mockResolvedValue({
        data: { quote_request_id: 3, status: 'awaiting_reply' },
      });
      const wrapper = await mountShow({ quote_request_resend_available: true });
      ScanSoloPipelineOpportunitiesAPI.show.mockClear();

      const button = wrapper.find(
        '[data-testid="resend-quote-request-button"]'
      );
      expect(button.text()).toBe('Reenviar solicitação de orçamento');
      await button.trigger('click');
      await flushPromises();

      expect(
        ScanSoloPipelineOpportunitiesAPI.resendQuoteRequest
      ).toHaveBeenCalledWith(7);
      expect(useAlert).toHaveBeenCalledWith(
        'Solicitação de orçamento reenviada.'
      );
      expect(ScanSoloPipelineOpportunitiesAPI.show).toHaveBeenCalledWith(7);
    });

    it('hides the resend action from non-admins and when it is not available', async () => {
      const agent = await mountShow(
        { quote_request_resend_available: true },
        { role: 'agent' }
      );
      expect(
        agent.find('[data-testid="resend-quote-request-button"]').exists()
      ).toBe(false);

      const unavailable = await mountShow({
        quote_request_resend_available: false,
      });
      expect(
        unavailable.find('[data-testid="resend-quote-request-button"]').exists()
      ).toBe(false);
    });

    it('shows the i18n message of a 422 quote_request_closed', async () => {
      ScanSoloPipelineOpportunitiesAPI.resendQuoteRequest.mockRejectedValue({
        response: { status: 422, data: { error: 'quote_request_closed' } },
      });
      const wrapper = await mountShow({ quote_request_resend_available: true });

      await wrapper
        .find('[data-testid="resend-quote-request-button"]')
        .trigger('click');
      await flushPromises();

      expect(useAlert).toHaveBeenCalledWith(
        'O orçamento desta oportunidade já foi respondido; não há solicitação para reenviar.'
      );
    });

    it('renders only translated text, never raw i18n keys', async () => {
      const wrapper = await mountShow({
        quote_request_resend_available: true,
        initial_template_failure: {
          reason: 'external_error',
          status: 'failed',
          occurred_at: '2026-01-01T08:00:00Z',
        },
      });

      expect(wrapper.text()).not.toContain('SCANSOLO.');
    });
  });
});
