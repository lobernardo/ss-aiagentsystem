import camelcaseKeys from 'camelcase-keys';
import { defineStore } from 'pinia';
import ScanSoloExecutionsAPI from 'dashboard/api/scansoloExecutions';
import ScanSoloProposalsAPI from 'dashboard/api/scansoloProposals';

const camelize = data => camelcaseKeys(data || {}, { deep: true });
const camelizeList = list => (list || []).map(camelize);

// RF-61 / CT-10: the Execuções screen reads the whole feed (attempt delivery
// evidence, template availability, Make dead letters and rejected
// callbacks, handoff events, recent errors, audit trail) from this store,
// exactly as the account-scoped executions endpoint returned it.
export const useScansoloExecutionsStore = defineStore('scansoloExecutions', {
  state: () => ({
    cadenceEvidence: [],
    templateAvailability: [],
    makeDeadLetters: [],
    makeCallbackErrors: [],
    handoffEvents: [],
    recentErrors: [],
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
        this.cadenceEvidence = camelizeList(data.cadence_evidence);
        this.templateAvailability = camelizeList(data.template_availability);
        this.makeDeadLetters = camelizeList(data.make_errors?.dead_letters);
        this.makeCallbackErrors = camelizeList(
          data.make_errors?.callback_errors
        );
        this.handoffEvents = camelizeList(data.handoff_events);
        this.recentErrors = camelizeList(data.recent_errors);
        this.auditEvents = camelizeList(data.audit_events);
      } finally {
        this.uiFlags.fetchingList = false;
      }
    },

    // RF-40: reprocessing a dead letter is the CT-04 retry with confirmation.
    async reprocessDeadLetter(deadLetter) {
      await ScanSoloProposalsAPI.retry(
        deadLetter.proposalId,
        deadLetter.proposalVersionId,
        true
      );
      await this.fetchExecutions();
    },
  },
});
