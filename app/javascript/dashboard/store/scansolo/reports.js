import camelcaseKeys from 'camelcase-keys';
import { defineStore } from 'pinia';
import ScanSoloReportsAPI from 'dashboard/api/scansoloReports';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';

// Switching tab/period quickly must never let an older response overwrite
// the report of the period now selected.
const reportRequest = useAbortableRequest();

// CT-01 / UI-02 / UI-10: the Relatórios screen reads the report, its loading
// flag and the last error from this store.
export const useScansoloReportsStore = defineStore('scansoloReports', {
  state: () => ({
    report: null,
    error: null,
    uiFlags: {
      fetching: false,
    },
  }),

  actions: {
    async fetchReport({ period, anchor }) {
      this.uiFlags.fetching = true;
      this.error = null;
      try {
        const response = await reportRequest.run(signal =>
          ScanSoloReportsAPI.get({ period, anchor }, { signal })
        );
        if (response) {
          this.report = camelcaseKeys(response.data, { deep: true });
        }
        return this.report;
      } catch (error) {
        this.error = error;
        return null;
      } finally {
        this.uiFlags.fetching = reportRequest.isPending.value;
      }
    },
  },
});
