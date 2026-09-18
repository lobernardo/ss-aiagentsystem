import ApiClient from './ApiClient';

class ScanSoloExecutionsAPI extends ApiClient {
  constructor() {
    super('scan_solo/executions', { accountScoped: true });
  }
}

export default new ScanSoloExecutionsAPI();
