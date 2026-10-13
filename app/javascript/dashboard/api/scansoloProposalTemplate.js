/* global axios */
import ApiClient from './ApiClient';

// CT-05: the account's active proposal template (singular resource).
class ScanSoloProposalTemplateAPI extends ApiClient {
  constructor() {
    super('scan_solo/proposal_template', { accountScoped: true });
  }

  show() {
    return axios.get(this.url);
  }

  // `formData` carries the `.docx` in the `file` field.
  upload(formData) {
    return axios.post(this.url, formData);
  }
}

export default new ScanSoloProposalTemplateAPI();
