import camelcaseKeys from 'camelcase-keys';
import { defineStore } from 'pinia';
import ScanSoloAiTurnsAPI from 'dashboard/api/scansoloAiTurns';

const camelizeTurn = data =>
  data ? camelcaseKeys(data, { deep: true }) : null;

// UI-04: per-turn telemetry/evidence viewer, queryable by correlation id
// (RF-24). `turns` backs the recent-turns list; `selectedTurn` is the
// single turn currently shown in the evidence panel.
export const useScansoloAiTurnsStore = defineStore('scansoloAiTurns', {
  state: () => ({
    turns: [],
    selectedTurn: null,
    uiFlags: {
      fetchingTurns: false,
      fetchingTurn: false,
    },
  }),

  actions: {
    async fetchTurns() {
      this.uiFlags.fetchingTurns = true;
      try {
        const { data } = await ScanSoloAiTurnsAPI.get();
        this.turns = data.map(camelizeTurn);
        return this.turns;
      } finally {
        this.uiFlags.fetchingTurns = false;
      }
    },

    async fetchTurn(correlationId) {
      this.uiFlags.fetchingTurn = true;
      try {
        const { data } = await ScanSoloAiTurnsAPI.show(correlationId);
        this.selectedTurn = camelizeTurn(data);
        return this.selectedTurn;
      } finally {
        this.uiFlags.fetchingTurn = false;
      }
    },
  },
});
