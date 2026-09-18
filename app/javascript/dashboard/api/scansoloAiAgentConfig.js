/* global axios */
import ApiClient from './ApiClient';

class ScanSoloAiAgentConfigAPI extends ApiClient {
  constructor() {
    super('scan_solo/ai_agent_config', { accountScoped: true });
  }

  updateDraft(payload) {
    return axios.put(`${this.url}/draft`, payload);
  }

  publish() {
    return axios.post(`${this.url}/publish`);
  }
}

export default new ScanSoloAiAgentConfigAPI();
