import ScanSoloReportsAPI from '../scansoloReports';
import ScanSoloQuoteRequestsAPI from '../scansoloQuoteRequests';
import ScanSoloPipelineOpportunitiesAPI from '../scansoloPipelineOpportunities';
import ApiClient from '../ApiClient';

describe('ScanSolo Relatórios API clients', () => {
  const originalAxios = window.axios;
  const axiosMock = {
    get: vi.fn(() => Promise.resolve()),
    post: vi.fn(() => Promise.resolve()),
  };

  beforeEach(() => {
    vi.clearAllMocks();
    window.axios = axiosMock;
    window.history.pushState({}, '', '/app/accounts/7/scansolo/reports');
  });

  afterEach(() => {
    window.axios = originalAxios;
    window.history.pushState({}, '', '/');
  });

  it('CT-01: gets the account-scoped report with period and anchor', () => {
    const { signal } = new AbortController();

    expect(ScanSoloReportsAPI).toBeInstanceOf(ApiClient);
    ScanSoloReportsAPI.get(
      { period: 'week', anchor: '2026-11-02' },
      { signal }
    );

    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/7/scan_solo/reports',
      { params: { period: 'week', anchor: '2026-11-02' }, signal }
    );
  });

  it('CT-01: works without a signal', () => {
    ScanSoloReportsAPI.get({ period: 'month', anchor: '2026-11-01' });

    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/7/scan_solo/reports',
      { params: { period: 'month', anchor: '2026-11-01' }, signal: undefined }
    );
  });

  it('CT-03: posts the single manual action without a body', () => {
    ScanSoloPipelineOpportunitiesAPI.markHandledManually(12);

    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/7/scan_solo/pipeline_opportunities/12/quote_request/handled_manually'
    );
  });

  it('CT-04: posts the bulk manual action with opportunity_ids', () => {
    ScanSoloQuoteRequestsAPI.bulkMarkHandledManually([1, 2]);

    expect(axiosMock.post).toHaveBeenCalledWith(
      '/api/v1/accounts/7/scan_solo/quote_requests/handled_manually',
      { opportunity_ids: [1, 2] }
    );
  });
});
