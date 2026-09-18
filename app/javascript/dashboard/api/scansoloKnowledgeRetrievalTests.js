/* global axios */
import ApiClient from './ApiClient';

class ScanSoloKnowledgeRetrievalTestsAPI extends ApiClient {
  constructor() {
    super('scan_solo/knowledge/retrieval_tests', { accountScoped: true });
  }

  run(query, topK) {
    return axios.post(this.url, { query, top_k: topK });
  }
}

export default new ScanSoloKnowledgeRetrievalTestsAPI();
