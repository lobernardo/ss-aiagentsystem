/* global axios */
import ApiClient from './ApiClient';

// CT-01: weekly or monthly report; `anchor` (YYYY-MM-DD) is any date inside
// the period. `signal` lets the caller cancel a superseded request.
class ScanSoloReportsAPI extends ApiClient {
  constructor() {
    super('scan_solo/reports', { accountScoped: true });
  }

  get({ period, anchor }, { signal } = {}) {
    return axios.get(this.url, { params: { period, anchor }, signal });
  }
}

export default new ScanSoloReportsAPI();
