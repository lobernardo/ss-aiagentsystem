/* global axios */
import ApiClient from './ApiClient';

// CT-11: a contact's ScanSolo opt-out marker.
class ScanSoloContactsAPI extends ApiClient {
  constructor() {
    super('scan_solo/contacts', { accountScoped: true });
  }

  getOptOut(contactId) {
    return axios.get(`${this.url}/${contactId}/opt_out`);
  }

  clearOptOut(contactId) {
    return axios.delete(`${this.url}/${contactId}/opt_out`);
  }
}

export default new ScanSoloContactsAPI();
