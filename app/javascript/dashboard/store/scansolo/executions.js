import camelcaseKeys from 'camelcase-keys';
import { defineStore } from 'pinia';
import ScanSoloExecutionsAPI from 'dashboard/api/scansoloExecutions';

const camelize = data => camelcaseKeys(data || {}, { deep: true });

// UI-09: the Execuções e auditoria screen reads cadence attempt evidence
// (RF-62), Make outbound dead-letter/inbound callback error visibility
// (RF-86), and action audit records (RF-46) exclusively from this store's
// state, reflecting whatever the account-scoped executions endpoint (T74)
// returned in one request.
export const useScansoloExecutionsStore = defineStore('scansoloExecutions', {
  state: () => ({
    cadenceEvidence: [],
    makeDeadLetters: [],
    makeCallbackErrors: [],
    auditEvents: [],
    uiFlags: {
      fetchingList: false,
    },
  }),

  actions: {
    async fetchExecutions() {
      this.uiFlags.fetchingList = true;
      try {
        const { data } = await ScanSoloExecutionsAPI.get();
        this.cadenceEvidence = (data.cadence_evidence || []).map(camelize);
        this.makeDeadLetters = (data.make_errors?.dead_letters || []).map(
          camelize
        );
        this.makeCallbackErrors = (data.make_errors?.callback_errors || []).map(
          camelize
        );
        this.auditEvents = (data.audit_events || []).map(camelize);
      } finally {
        this.uiFlags.fetchingList = false;
      }
    },
  },
});
