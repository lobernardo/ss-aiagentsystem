import camelcaseKeys from 'camelcase-keys';
import { defineStore } from 'pinia';
import ScanSoloCadenceEnrollmentsAPI from 'dashboard/api/scansoloCadenceEnrollments';

const camelizeEnrollment = data => camelcaseKeys(data || {}, { deep: true });

// UI-07: the Follow-ups screen reads active/paused cadence enrollments
// exclusively from this store's state, reflecting whatever the server
// persisted for pause/resume/cancel within the same request/response cycle
// (RF-64).
export const useScansoloCadenceEnrollmentsStore = defineStore(
  'scansoloCadenceEnrollments',
  {
    state: () => ({
      enrollments: [],
      uiFlags: {
        fetchingList: false,
      },
    }),

    actions: {
      upsertEnrollment(enrollment) {
        const index = this.enrollments.findIndex(e => e.id === enrollment.id);
        if (index === -1) {
          this.enrollments.push(enrollment);
        } else {
          this.enrollments[index] = enrollment;
        }
      },

      async fetchEnrollments() {
        this.uiFlags.fetchingList = true;
        try {
          const { data } = await ScanSoloCadenceEnrollmentsAPI.get();
          this.enrollments = camelizeEnrollment(data);
          return this.enrollments;
        } finally {
          this.uiFlags.fetchingList = false;
        }
      },

      async pauseEnrollment(id) {
        const { data } = await ScanSoloCadenceEnrollmentsAPI.pause(id);
        this.upsertEnrollment(camelizeEnrollment(data));
      },

      async resumeEnrollment(id) {
        const { data } = await ScanSoloCadenceEnrollmentsAPI.resume(id);
        this.upsertEnrollment(camelizeEnrollment(data));
      },

      async cancelEnrollment(id) {
        const { data } = await ScanSoloCadenceEnrollmentsAPI.cancel(id);
        this.upsertEnrollment(camelizeEnrollment(data));
      },
    },
  }
);
