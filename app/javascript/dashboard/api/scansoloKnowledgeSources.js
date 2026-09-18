/* global axios */
import ApiClient from './ApiClient';

class ScanSoloKnowledgeSourcesAPI extends ApiClient {
  constructor() {
    super('scan_solo/knowledge/sources', { accountScoped: true });
  }

  reindex(id) {
    return axios.post(`${this.url}/${id}/reindex`);
  }
}

export default new ScanSoloKnowledgeSourcesAPI();
