import camelcaseKeys from 'camelcase-keys';
import { defineStore } from 'pinia';
import ScanSoloCadenceTemplatesAPI from 'dashboard/api/scansoloCadenceTemplates';

const camelize = data => camelcaseKeys(data || {}, { deep: true });
const sameRow = (row, other) =>
  row.stage === other.stage && row.step === other.step;

// UI-12: template rows (mapping + Meta availability) exactly as the server
// reported them; an edit replaces the row with the server's response.
export const useScansoloCadenceTemplatesStore = defineStore(
  'scansoloCadenceTemplates',
  {
    state: () => ({
      rows: [],
      uiFlags: {
        fetchingList: false,
        saving: false,
      },
    }),

    actions: {
      async fetchRows() {
        this.uiFlags.fetchingList = true;
        try {
          const { data } = await ScanSoloCadenceTemplatesAPI.get();
          this.rows = data.map(camelize);
          return this.rows;
        } finally {
          this.uiFlags.fetchingList = false;
        }
      },

      async updateRow({ stage, step, templateName, language, params }) {
        this.uiFlags.saving = true;
        try {
          const { data } = await ScanSoloCadenceTemplatesAPI.update({
            stage,
            step,
            template_name: templateName,
            language,
            params,
          });
          const row = camelize(data);
          const index = this.rows.findIndex(existing => sameRow(existing, row));
          if (index === -1) this.rows.push(row);
          else this.rows[index] = row;
          return row;
        } finally {
          this.uiFlags.saving = false;
        }
      },
    },
  }
);
