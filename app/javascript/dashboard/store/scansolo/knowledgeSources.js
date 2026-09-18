import camelcaseKeys from 'camelcase-keys';
import { defineStore } from 'pinia';
import ScanSoloKnowledgeSourcesAPI from 'dashboard/api/scansoloKnowledgeSources';
import ScanSoloKnowledgeRetrievalTestsAPI from 'dashboard/api/scansoloKnowledgeRetrievalTests';

const camelize = data => camelcaseKeys(data || {}, { deep: true });

// UI-05: every Knowledge screen operation (upload/FAQ/company-info entry,
// enable/disable, reindex, retrieval simulator) round-trips through this
// store so the list and the simulator results always reflect what the
// server persisted, never a locally-guessed outcome.
export const useScansoloKnowledgeStore = defineStore('scansoloKnowledge', {
  state: () => ({
    sources: [],
    retrievalResults: [],
    retrievalFailureReason: null,
    uiFlags: {
      fetchingList: false,
      creating: false,
      running: false,
    },
  }),

  actions: {
    upsertSource(source) {
      const index = this.sources.findIndex(s => s.id === source.id);
      if (index === -1) {
        this.sources.unshift(source);
      } else {
        this.sources[index] = source;
      }
    },

    async fetchSources() {
      this.uiFlags.fetchingList = true;
      try {
        const { data } = await ScanSoloKnowledgeSourcesAPI.get();
        this.sources = data.map(camelize);
        return this.sources;
      } finally {
        this.uiFlags.fetchingList = false;
      }
    },

    async createSource(payload) {
      this.uiFlags.creating = true;
      try {
        const { data } = await ScanSoloKnowledgeSourcesAPI.create(payload);
        const source = camelize(data);
        this.upsertSource(source);
        return source;
      } finally {
        this.uiFlags.creating = false;
      }
    },

    async toggleEnabled(id, enabled) {
      const { data } = await ScanSoloKnowledgeSourcesAPI.update(id, {
        enabled,
      });
      const source = camelize(data);
      this.upsertSource(source);
      return source;
    },

    async reindexSource(id) {
      const { data } = await ScanSoloKnowledgeSourcesAPI.reindex(id);
      const source = camelize(data);
      this.upsertSource(source);
      return source;
    },

    async deleteSource(id) {
      await ScanSoloKnowledgeSourcesAPI.delete(id);
      this.sources = this.sources.filter(source => source.id !== id);
    },

    async runRetrievalTest(query, topK) {
      this.uiFlags.running = true;
      try {
        const { data } = await ScanSoloKnowledgeRetrievalTestsAPI.run(
          query,
          topK
        );
        this.retrievalResults = (data.results || []).map(camelize);
        this.retrievalFailureReason = data.failure_reason || null;
        return this.retrievalResults;
      } finally {
        this.uiFlags.running = false;
      }
    },
  },
});
