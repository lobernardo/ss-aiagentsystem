/* global axios */
import ApiClient from './ApiClient';

// CT-03: template mapping and availability per cadence stage/step and for
// the proposal send (`step: null`).
class ScanSoloCadenceTemplatesAPI extends ApiClient {
  constructor() {
    super('scan_solo/cadence_templates', { accountScoped: true });
  }

  update(payload) {
    return axios.put(this.url, payload);
  }
}

export default new ScanSoloCadenceTemplatesAPI();
