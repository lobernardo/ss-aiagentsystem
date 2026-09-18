/* global axios */
import ApiClient from './ApiClient';

class ScanSoloHandoffAPI extends ApiClient {
  constructor() {
    super('scan_solo/conversations', { accountScoped: true });
  }

  controlState(conversationId) {
    return axios.get(`${this.url}/${conversationId}/control_state`);
  }

  takeover(conversationId, reason) {
    return axios.post(`${this.url}/${conversationId}/handoff`, { reason });
  }

  returnToAi(conversationId) {
    return axios.post(`${this.url}/${conversationId}/return_to_ai`);
  }
}

export default new ScanSoloHandoffAPI();
