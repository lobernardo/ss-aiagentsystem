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

  // CT-03: the reason is required (422 `reason_required` otherwise).
  reject(proposalId, proposalVersionId, reason) {
    return axios.post(`${this.url}/${proposalId}/reject`, {
      proposal_version_id: proposalVersionId,
      reason,
    });
  }

  send(proposalId, proposalVersionId, correlationId) {
    return axios.post(`${this.url}/${proposalId}/send`, {
      proposal_version_id: proposalVersionId,
      correlation_id: correlationId,
    });
  }

  // CT-04: `confirm_reprocess: true` is required for a dead-lettered operation.
  retry(proposalId, proposalVersionId, confirmReprocess) {
    return axios.post(`${this.url}/${proposalId}/retry`, {
      proposal_version_id: proposalVersionId,
      confirm_reprocess: confirmReprocess,
    });
  }
}

export default new ScanSoloProposalsAPI();
