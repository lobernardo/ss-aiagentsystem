import { setActivePinia, createPinia } from 'pinia';
import ScanSoloReportsAPI from 'dashboard/api/scansoloReports';
import { useScansoloReportsStore } from '../reports';

vi.mock('dashboard/api/scansoloReports', () => ({
  default: { get: vi.fn() },
}));

const reportPayload = {
  period: 'week',
  anchor: '2026-11-02',
  source: 'snapshot',
  generated_at: '2026-11-09T06:00:00-03:00',
  summary: {
    new_leads: {
      total: 3,
      by_source: { website: 2, manual: 1, nao_informada: 0 },
    },
    first_response_minutes: { median: 4, p90: 12 },
  },
  funnel: [{ stage: 'novo_lead', active: 2, stalled: 1 }],
  stalled: [
    {
      opportunity_id: 9,
      contact_name: 'Ana',
      stage: 'qualificado',
      last_customer_interaction_at: null,
      commercial_status: 'aguardando_artur',
      stall_reason: 'aguardando_artur',
      suggested_action: 'SCANSOLO.REPORTS.SUGGESTED_ACTIONS.AGUARDANDO_ARTUR',
    },
  ],
};

describe('useScansoloReportsStore#fetchReport', () => {
  let store;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    store = useScansoloReportsStore();
  });

  it('stores the deep-camelized report and toggles uiFlags.fetching', async () => {
    let resolveRequest;
    ScanSoloReportsAPI.get.mockReturnValue(
      new Promise(resolve => {
        resolveRequest = resolve;
      })
    );

    const pending = store.fetchReport({ period: 'week', anchor: '2026-11-02' });

    expect(store.uiFlags.fetching).toBe(true);
    expect(ScanSoloReportsAPI.get).toHaveBeenCalledWith(
      { period: 'week', anchor: '2026-11-02' },
      { signal: expect.any(AbortSignal) }
    );

    resolveRequest({ data: reportPayload });
    await pending;

    expect(store.uiFlags.fetching).toBe(false);
    expect(store.error).toBeNull();
    expect(store.report).toMatchObject({
      source: 'snapshot',
      generatedAt: '2026-11-09T06:00:00-03:00',
      summary: {
        newLeads: { total: 3, bySource: { website: 2, manual: 1 } },
        firstResponseMinutes: { median: 4, p90: 12 },
      },
      funnel: [{ stage: 'novo_lead', active: 2, stalled: 1 }],
      stalled: [
        {
          opportunityId: 9,
          contactName: 'Ana',
          lastCustomerInteractionAt: null,
          commercialStatus: 'aguardando_artur',
          stallReason: 'aguardando_artur',
          suggestedAction:
            'SCANSOLO.REPORTS.SUGGESTED_ACTIONS.AGUARDANDO_ARTUR',
        },
      ],
    });
  });

  it('keeps the error and turns fetching off when the request fails', async () => {
    const failure = {
      response: { status: 422, data: { error: 'invalid_anchor' } },
    };
    ScanSoloReportsAPI.get.mockRejectedValue(failure);

    await store.fetchReport({ period: 'week', anchor: '2026-02-30' });

    expect(store.error).toEqual(failure);
    expect(store.report).toBeNull();
    expect(store.uiFlags.fetching).toBe(false);
  });

  it('clears a previous error on a new successful fetch', async () => {
    ScanSoloReportsAPI.get.mockRejectedValueOnce(new Error('boom'));
    await store.fetchReport({ period: 'week', anchor: '2026-11-02' });
    expect(store.error).not.toBeNull();

    ScanSoloReportsAPI.get.mockResolvedValueOnce({ data: reportPayload });
    await store.fetchReport({ period: 'week', anchor: '2026-11-02' });

    expect(store.error).toBeNull();
    expect(store.report.period).toBe('week');
  });

  it('ignores the response of a superseded request', async () => {
    let resolveFirst;
    ScanSoloReportsAPI.get
      .mockImplementationOnce(
        (_params, { signal }) =>
          new Promise((resolve, reject) => {
            resolveFirst = resolve;
            signal.addEventListener('abort', () => {
              const error = new Error('canceled');
              error.name = 'CanceledError';
              reject(error);
            });
          })
      )
      .mockResolvedValueOnce({ data: { ...reportPayload, period: 'month' } });

    const first = store.fetchReport({ period: 'week', anchor: '2026-11-02' });
    const second = store.fetchReport({ period: 'month', anchor: '2026-11-01' });
    resolveFirst({ data: reportPayload });
    await Promise.all([first, second]);

    expect(store.report.period).toBe('month');
    expect(store.error).toBeNull();
    expect(store.uiFlags.fetching).toBe(false);
  });
});
