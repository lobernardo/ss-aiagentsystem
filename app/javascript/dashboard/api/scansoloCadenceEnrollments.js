/* global axios */
import ApiClient from './ApiClient';

class ScanSoloCadenceEnrollmentsAPI extends ApiClient {
  constructor() {
    super('scan_solo/cadence_enrollments', { accountScoped: true });
  }

  enroll(opportunityId, cadenceDefinitionId) {
    return axios.post(this.url, {
      opportunity_id: opportunityId,
      cadence_definition_id: cadenceDefinitionId,
    });
  }

  pause(id) {
    return axios.post(`${this.url}/${id}/pause`);
  }

  resume(id) {
    return axios.post(`${this.url}/${id}/resume`);
  }

  cancel(id) {
    return axios.post(`${this.url}/${id}/cancel`);
  }
}

export default new ScanSoloCadenceEnrollmentsAPI();
