import {
  mount,
  flushPromises,
  enableAutoUnmount,
  RouterLinkStub,
} from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { withFullI18n } from 'test-i18n';
import ScanSoloReportsAPI from 'dashboard/api/scansoloReports';
import { SCANSOLO_PIPELINE_STAGES } from '../../pipeline/pipelineConstants';
import Reports from '../Reports.vue';

vi.mock('dashboard/api/scansoloReports', () => ({
  default: { get: vi.fn() },
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1 } }),
  useRouter: () => ({ push: vi.fn() }),
}));

withFullI18n();
enableAutoUnmount(afterEach);

// Saturday 07/11/2026 10:00 in São Paulo.
const NOW = new Date('2026-11-07T13:00:00Z');
const DAY_MS = 24 * 60 * 60 * 1000;
const daysAgo = days => new Date(NOW.getTime() - days * DAY_MS).toISOString();

const buildSummary = base => ({
  new_leads: {
    total: base,
    by_source: { website: base - 1, manual: 1, nao_informada: 0 },
  },
  responded: { total: base + 1 },
  first_response_minutes: { median: base + 2, p90: null },
  ai_turns: {
    by_status: { pending: 0, suppressed: 1, succeeded: base + 3, failed: 2 },
    by_reason: [{ status: 'failed', reason: 'stale_pending', count: 2 }],
  },
  inbound_without_turn: { total: base + 4 },
  cadence_attempts: {
    by_result: {
      scheduled: 0,
      dispatched: 0,
      sent: base + 5,
      skipped: 1,
      failed: 0,
      cancelled: 0,
    },
    by_block_reason: [{ reason: 'template_missing', count: 1 }],
  },
  qualified: { total: base + 6 },
  forwarded: { total: base + 7 },
  proposals: {
    by_status: {
      generating: 0,
      generated: 0,
      approved: 0,
      sent: base + 8,
      failed: 0,
      awaiting_approval: 3,
      rejected: 0,
    },
  },
});

const stalledItems = [
  {
    opportunity_id: 11,
    contact_name: 'Ada Lovelace',
    stage: 'qualificado',
    last_customer_interaction_at: daysAgo(3),
    created_at: daysAgo(10),
    commercial_status: 'aguardando_artur',
    stall_reason: 'aguardando_artur',
    suggested_action: 'SCANSOLO.REPORTS.SUGGESTED_ACTIONS.AGUARDANDO_ARTUR',
  },
  {
    opportunity_id: 12,
    contact_name: 'Grace Hopper',
    stage: 'proposta_enviada',
    last_customer_interaction_at: null,
    created_at: daysAgo(5),
    commercial_status: 'proposta_enviada_manual',
    stall_reason: 'proposta_manual_sem_cadencia',
    suggested_action:
      'SCANSOLO.REPORTS.SUGGESTED_ACTIONS.PROPOSTA_MANUAL_SEM_CADENCIA',
  },
  {
    opportunity_id: 13,
    contact_name: 'Katherine Johnson',
    stage: 'novo_lead',
    last_customer_interaction_at: daysAgo(2),
    created_at: daysAgo(2),
    commercial_status: 'nao_encaminhado',
    stall_reason: 'outro',
    suggested_action: 'SCANSOLO.REPORTS.SUGGESTED_ACTIONS.OUTRO',
  },
];

// Backend order is not pipeline order: the screen must reorder it.
const funnel = [...SCANSOLO_PIPELINE_STAGES].reverse().map((stage, index) => ({
  stage,
  active: index + 1,
  stalled: index,
}));

const buildReport = overrides => ({
  period: 'week',
  anchor: '2026-11-02',
  timezone: 'America/Sao_Paulo',
  starts_at: '2026-11-02T00:00:00-03:00',
  ends_at: '2026-11-09T00:00:00-03:00',
  source: 'live',
  generated_at: '2026-11-07T10:00:00-03:00',
  as_of: '2026-11-07T10:00:00-03:00',
  summary: buildSummary(10),
  previous: {
    starts_at: '2026-10-26T00:00:00-03:00',
    ends_at: '2026-11-02T00:00:00-03:00',
    summary: buildSummary(20),
  },
  funnel,
  stalled: stalledItems,
  ...overrides,
});

const mountReports = async () => {
  const wrapper = mount(Reports, {
    global: { stubs: { RouterLink: RouterLinkStub } },
  });
  await flushPromises();
  return wrapper;
};

const kpi = (wrapper, key) =>
  wrapper.find(`[data-testid="report-kpi"][data-kpi="${key}"]`);

const kpiItem = (wrapper, key, item) =>
  kpi(wrapper, key).find(
    `[data-testid="report-kpi-item"][data-item="${item}"]`
  );

describe('Reports', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(NOW);
    setActivePinia(createPinia());
    ScanSoloReportsAPI.get.mockResolvedValue({ data: buildReport() });
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  describe('UI-02: period tabs and selector', () => {
    it('opens on the current week and fetches it', async () => {
      const wrapper = await mountReports();

      expect(ScanSoloReportsAPI.get).toHaveBeenCalledTimes(1);
      expect(ScanSoloReportsAPI.get).toHaveBeenCalledWith(
        { period: 'week', anchor: '2026-11-02' },
        expect.anything()
      );
      expect(
        wrapper.find('[data-testid="report-period-select"] select').element
          .value
      ).toBe('2026-11-02');
    });

    it('offers the current week and the 2 previous ones as pt-BR ranges', async () => {
      const wrapper = await mountReports();

      const options = wrapper.findAll(
        '[data-testid="report-period-select"] option'
      );
      expect(options.map(option => option.text())).toEqual([
        '02/11/2026 a 08/11/2026',
        '26/10/2026 a 01/11/2026',
        '19/10/2026 a 25/10/2026',
      ]);
    });

    it('fetches the previous week anchored on its Monday', async () => {
      const wrapper = await mountReports();

      await wrapper
        .find('[data-testid="report-period-select"] select')
        .setValue('2026-10-26');
      await flushPromises();

      expect(ScanSoloReportsAPI.get).toHaveBeenLastCalledWith(
        { period: 'week', anchor: '2026-10-26' },
        expect.anything()
      );
    });

    it('switches to the month tab with the current and previous month', async () => {
      const wrapper = await mountReports();

      const monthTab = wrapper
        .findAll('[data-testid="report-tabs"] button')
        .find(button => button.text() === 'Mês');
      await monthTab.trigger('click');
      await flushPromises();

      expect(ScanSoloReportsAPI.get).toHaveBeenCalledTimes(2);
      expect(ScanSoloReportsAPI.get).toHaveBeenLastCalledWith(
        { period: 'month', anchor: '2026-11-01' },
        expect.anything()
      );
      const options = wrapper.findAll(
        '[data-testid="report-period-select"] option'
      );
      expect(options.map(option => option.text())).toEqual([
        '01/11/2026 a 30/11/2026',
        '01/10/2026 a 31/10/2026',
      ]);
    });
  });

  describe('UI-03: KPI cards', () => {
    it('renders each KPI with the previous period value', async () => {
      const wrapper = await mountReports();

      const headline = {
        new_leads: ['10', '20'],
        responded: ['11', '21'],
        qualified: ['16', '26'],
        forwarded: ['17', '27'],
        inbound_without_turn: ['14', '24'],
      };
      Object.entries(headline).forEach(([key, [value, previous]]) => {
        const card = kpi(wrapper, key);
        expect(card.find('[data-testid="report-kpi-value"]').text()).toBe(
          value
        );
        expect(card.find('[data-testid="report-kpi-previous"]').text()).toBe(
          `Período anterior: ${previous}`
        );
      });

      const breakdown = [
        ['new_leads', 'website', '9', '19'],
        ['new_leads', 'nao_informada', '0', '0'],
        ['first_response', 'median', '12 min', '22 min'],
        ['ai_turns', 'succeeded', '13', '23'],
        ['ai_turn_reasons', 'failed:stale_pending', '2', '2'],
        ['cadence_attempts', 'sent', '15', '25'],
        ['cadence_block_reasons', ':template_missing', '1', '1'],
        ['proposals', 'sent', '18', '28'],
        ['proposals', 'awaiting_approval', '3', '3'],
      ];
      breakdown.forEach(([key, item, value, previous]) => {
        const line = kpiItem(wrapper, key, item);
        expect(line.find('[data-testid="report-kpi-item-value"]').text()).toBe(
          value
        );
        expect(
          line.find('[data-testid="report-kpi-item-previous"]').text()
        ).toBe(`Período anterior: ${previous}`);
      });

      expect(
        kpiItem(wrapper, 'first_response', 'p90')
          .find('[data-testid="report-kpi-item-value"]')
          .text()
      ).toBe('—');
      expect(kpiItem(wrapper, 'new_leads', 'website').text()).toContain('Site');
      expect(
        kpiItem(wrapper, 'proposals', 'awaiting_approval').text()
      ).toContain('Aguardando aprovação');
    });

    it('shows no frozen-data notice for a live report', async () => {
      const wrapper = await mountReports();

      expect(
        wrapper.find('[data-testid="report-snapshot-notice"]').exists()
      ).toBe(false);
    });

    it('shows the frozen-data notice with generated_at for a snapshot', async () => {
      ScanSoloReportsAPI.get.mockResolvedValue({
        data: buildReport({
          source: 'snapshot',
          generated_at: '2026-11-09T06:00:00-03:00',
        }),
      });
      const wrapper = await mountReports();

      expect(
        wrapper.find('[data-testid="report-snapshot-notice"]').text()
      ).toBe('Dados congelados em 09/11/2026 06:00');
    });
  });

  describe('UI-04: funnel', () => {
    it('renders the 8 stages in pipeline order with active and stalled', async () => {
      const wrapper = await mountReports();

      const rows = wrapper.findAll('[data-testid="funnel-row"]');
      expect(rows.map(row => row.attributes('data-stage'))).toEqual(
        SCANSOLO_PIPELINE_STAGES
      );
      const novoLead = rows[0];
      expect(novoLead.find('[data-testid="funnel-stage"]').text()).toBe(
        'Novo Lead'
      );
      expect(novoLead.find('[data-testid="funnel-active"]').text()).toBe('8');
      expect(novoLead.find('[data-testid="funnel-stalled"]').text()).toBe('7');
    });
  });

  describe('UI-05: stalled table', () => {
    const row = (wrapper, id) =>
      wrapper.find(`[data-testid="stalled-row"][data-opportunity-id="${id}"]`);

    it('groups one row per stalled lead by stage, in pipeline order', async () => {
      const wrapper = await mountReports();

      expect(wrapper.findAll('[data-testid="stalled-row"]')).toHaveLength(3);
      expect(
        wrapper
          .findAll('[data-testid="stalled-group"]')
          .map(group => group.attributes('data-stage'))
      ).toEqual(['novo_lead', 'qualificado', 'proposta_enviada']);
    });

    it('translates the commercial status, reason and suggested action', async () => {
      const wrapper = await mountReports();

      const artur = row(wrapper, 11);
      expect(
        artur.find('[data-testid="stalled-commercial-status"]').text()
      ).toBe('Aguardando o Artur');
      expect(artur.find('[data-testid="stalled-reason"]').text()).toBe(
        'Aguardando o Artur'
      );
      expect(artur.find('[data-testid="stalled-action"]').text()).toBe(
        'Cobrar resposta do Artur'
      );

      const manual = row(wrapper, 12);
      expect(manual.find('[data-testid="stalled-reason"]').text()).toBe(
        'Proposta manual sem cadência'
      );
      expect(manual.find('[data-testid="stalled-action"]').text()).toBe(
        'Acompanhar com o Artur'
      );

      const other = row(wrapper, 13);
      expect(other.find('[data-testid="stalled-reason"]').text()).toBe('Outro');
      expect(other.find('[data-testid="stalled-action"]').text()).toBe(
        'Revisar manualmente'
      );
    });

    it('labels an escalado_wa lead with the Artur commercial status', async () => {
      ScanSoloReportsAPI.get.mockResolvedValue({
        data: buildReport({
          stalled: [
            {
              ...stalledItems[0],
              opportunity_id: 14,
              stage: 'negociacao',
              commercial_status: 'escalado_wa',
            },
          ],
        }),
      });
      const wrapper = await mountReports();

      expect(
        row(wrapper, 14)
          .find('[data-testid="stalled-commercial-status"]')
          .text()
      ).toBe('Encaminhado ao Artur (WhatsApp)');
    });

    it('counts days from the last interaction, or from created_at when it is null', async () => {
      const wrapper = await mountReports();

      expect(row(wrapper, 11).find('[data-testid="stalled-days"]').text()).toBe(
        '3 dias'
      );
      expect(row(wrapper, 12).find('[data-testid="stalled-days"]').text()).toBe(
        '5 dias'
      );
    });

    it('links the lead name to the opportunity detail', async () => {
      const wrapper = await mountReports();

      const link = row(wrapper, 11).findComponent(RouterLinkStub);
      expect(link.text()).toBe('Ada Lovelace');
      expect(link.props('to')).toEqual({
        name: 'scansolo_pipeline_opportunity_detail',
        params: { accountId: 1, opportunityId: 11 },
      });
    });

    it('shows the empty message when nothing is stalled', async () => {
      ScanSoloReportsAPI.get.mockResolvedValue({
        data: buildReport({ stalled: [] }),
      });
      const wrapper = await mountReports();

      expect(wrapper.find('[data-testid="stalled-empty"]').text()).toBe(
        'Nenhum lead parado no momento.'
      );
    });
  });

  describe('UI-10: loading, error and empty states', () => {
    it('shows the loading state while the GET is in flight', async () => {
      ScanSoloReportsAPI.get.mockReturnValue(new Promise(() => {}));
      const wrapper = mount(Reports, {
        global: { stubs: { RouterLink: RouterLinkStub } },
      });
      await flushPromises();

      expect(wrapper.find('[data-testid="list-state-loading"]').text()).toBe(
        'Carregando relatório…'
      );
    });

    it('shows the error state and retries the same period', async () => {
      ScanSoloReportsAPI.get.mockRejectedValueOnce(new Error('boom'));
      const wrapper = await mountReports();

      expect(wrapper.find('[data-testid="list-state-error"]').text()).toContain(
        'Não foi possível carregar o relatório.'
      );

      await wrapper.find('[data-testid="list-state-retry"]').trigger('click');
      await flushPromises();

      expect(ScanSoloReportsAPI.get).toHaveBeenCalledTimes(2);
      expect(ScanSoloReportsAPI.get).toHaveBeenLastCalledWith(
        { period: 'week', anchor: '2026-11-02' },
        expect.anything()
      );
      expect(wrapper.find('[data-testid="list-state-error"]').exists()).toBe(
        false
      );
      expect(
        wrapper.findAll('[data-testid="report-kpi"]').length
      ).toBeGreaterThan(0);
    });

    it('shows the empty state without leads or opportunities', async () => {
      ScanSoloReportsAPI.get.mockResolvedValue({
        data: buildReport({
          summary: {
            ...buildSummary(0),
            new_leads: { total: 0, by_source: {} },
          },
          funnel: SCANSOLO_PIPELINE_STAGES.map(stage => ({
            stage,
            active: 0,
            stalled: 0,
          })),
          stalled: [],
        }),
      });
      const wrapper = await mountReports();

      expect(wrapper.find('[data-testid="list-state-empty"]').text()).toBe(
        'Sem dados para este período.'
      );
    });
  });

  it('never renders phone or e-mail', async () => {
    const wrapper = await mountReports();

    expect(wrapper.html()).not.toMatch(/@|\+55/);
  });
});
