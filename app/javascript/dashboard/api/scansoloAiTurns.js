import ApiClient from './ApiClient';

class ScanSoloAiTurnsAPI extends ApiClient {
  constructor() {
    super('scan_solo/ai_turns', { accountScoped: true });
  }
}

export default new ScanSoloAiTurnsAPI();
