import camelcaseKeys from 'camelcase-keys';
import { defineStore } from 'pinia';
import ScanSoloAiAgentConfigAPI from 'dashboard/api/scansoloAiAgentConfig';

const camelizeConfig = data =>
  data ? camelcaseKeys(data, { deep: true }) : null;

// UI-03: the draft is edited freely and never affects what a live
// conversation reads (RF-22) — only an explicit publish() call swaps the
// `published` state to a new atomic snapshot of the draft.
export const useScansoloAiAgentConfigStore = defineStore(
  'scansoloAiAgentConfig',
  {
    state: () => ({
      draft: null,
      published: null,
      availableModels: [],
      uiFlags: {
        fetching: false,
        updatingDraft: false,
        publishing: false,
      },
    }),

    actions: {
      async fetch() {
        this.uiFlags.fetching = true;
        try {
          const { data } = await ScanSoloAiAgentConfigAPI.get();
          this.draft = camelizeConfig(data.draft);
          this.published = camelizeConfig(data.published);
          this.availableModels = data.available_models || [];
          return { draft: this.draft, published: this.published };
        } finally {
          this.uiFlags.fetching = false;
        }
      },

      async updateDraft(payload) {
        this.uiFlags.updatingDraft = true;
        try {
          const { data } = await ScanSoloAiAgentConfigAPI.updateDraft(payload);
          this.draft = camelizeConfig(data);
          return this.draft;
        } finally {
          this.uiFlags.updatingDraft = false;
        }
      },

      async publish() {
        this.uiFlags.publishing = true;
        try {
          const { data } = await ScanSoloAiAgentConfigAPI.publish();
          this.published = camelizeConfig(data);
          return this.published;
        } finally {
          this.uiFlags.publishing = false;
        }
      },
    },
  }
);
