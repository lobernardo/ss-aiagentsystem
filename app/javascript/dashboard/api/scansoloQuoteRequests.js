/* global axios */
import ApiClient from './ApiClient';

class ScanSoloQuoteRequestsAPI extends ApiClient {
  constructor() {
    super('scan_solo/quote_requests', { accountScoped: true });
  }

  // CT-04: answers 200 with one `{ opportunity_id, result }` per id.
  bulkMarkHandledManually(ids) {
    return axios.post(`${this.url}/handled_manually`, {
      opportunity_ids: ids,
    });
  }
}

export default new ScanSoloQuoteRequestsAPI();
