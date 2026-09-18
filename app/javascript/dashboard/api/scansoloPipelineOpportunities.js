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
}

export default new ScanSoloPipelineOpportunitiesAPI();
