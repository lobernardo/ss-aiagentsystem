/* global axios */
import ApiClient from './ApiClient';

class ScanSoloProposalsAPI extends ApiClient {
  constructor() {
    super('scan_solo/proposals', { accountScoped: true });
  }

  generate(opportunityId, correlationId) {
    return axios.post(
      `${this.baseUrl()}/scan_solo/pipeline_opportunities/${opportunityId}/proposals/generate`,
      { correlation_id: correlationId }
    );
  }

  approve(proposalId, proposalVersionId, correlationId) {
    return axios.post(`${this.url}/${proposalId}/approve`, {
      proposal_version_id: proposalVersionId,
      correlation_id: correlationId,
    });
  }

  send(proposalId, proposalVersionId, correlationId) {
    return axios.post(`${this.url}/${proposalId}/send`, {
      proposal_version_id: proposalVersionId,
      correlation_id: correlationId,
    });
  }
}

export default new ScanSoloProposalsAPI();
