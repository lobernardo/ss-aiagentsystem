/* global axios */
import ApiClient from './ApiClient';

// CT-08: quote replies pending a manual decision (UI-05).
class ScanSoloQuoteRepliesAPI extends ApiClient {
  constructor() {
    super('scan_solo/quote_replies', { accountScoped: true });
  }

  getPending() {
    return axios.get(this.url, { params: { status: 'pending' } });
  }

  link(id, quoteRequestId) {
    return axios.post(`${this.url}/${id}/link`, {
      quote_request_id: quoteRequestId,
    });
  }

  discard(id) {
    return axios.post(`${this.url}/${id}/discard`);
  }
}

export default new ScanSoloQuoteRepliesAPI();
