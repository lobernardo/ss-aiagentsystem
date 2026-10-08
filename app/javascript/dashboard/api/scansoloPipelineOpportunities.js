/* global axios */
import ApiClient from './ApiClient';

class ScanSoloPipelineOpportunitiesAPI extends ApiClient {
  constructor() {
    super('scan_solo/pipeline_opportunities', { accountScoped: true });
  }

  stageTransition(id, targetStage) {
    return axios.post(`${this.url}/${id}/stage_transitions`, {
      target_stage: targetStage,
    });
  }

  // CT-09: written to the opportunity's native Contact.
  updateLeadEmail(id, email) {
    return axios.patch(`${this.url}/${id}`, { email });
  }

  // CT-12: administrators only; no body.
  resendQuoteRequest(id) {
    return axios.post(`${this.url}/${id}/quote_request/resend`);
  }
}

export default new ScanSoloPipelineOpportunitiesAPI();
