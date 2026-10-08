import camelcaseKeys from 'camelcase-keys';
import { defineStore } from 'pinia';
import ScanSoloPipelineOpportunitiesAPI from 'dashboard/api/scansoloPipelineOpportunities';

const camelizeOpportunity = data => camelcaseKeys(data || {}, { deep: true });

// UI-01: the Kanban board reads opportunity stage exclusively from this
// store's state, so a card only ever appears to move once the server has
// confirmed the transition (or reverts if the server rejects it) — never
// from a locally-guessed outcome.
export const useScansoloPipelineOpportunitiesStore = defineStore(
  'scansoloPipelineOpportunities',
  {
    state: () => ({
      opportunities: [],
      uiFlags: {
        fetchingList: false,
      },
    }),

    getters: {
      byStage: state => stage =>
        state.opportunities.filter(opportunity => opportunity.stage === stage),
    },

    actions: {
      upsertOpportunity(opportunity) {
        const index = this.opportunities.findIndex(
          o => o.id === opportunity.id
        );
        if (index === -1) {
          this.opportunities.push(opportunity);
        } else {
          this.opportunities[index] = opportunity;
        }
      },

      async fetchOpportunities() {
        this.uiFlags.fetchingList = true;
        try {
          const { data } = await ScanSoloPipelineOpportunitiesAPI.get();
          this.opportunities = camelizeOpportunity(data);
          return this.opportunities;
        } finally {
          this.uiFlags.fetchingList = false;
        }
      },

      // UI-01 / CT-01: a manual lead lands on the board as soon as the
      // server creates it; a 422 propagates so the form shows the reason.
      async createOpportunity(payload) {
        const { data } = await ScanSoloPipelineOpportunitiesAPI.create(payload);
        const opportunity = camelizeOpportunity(data);
        this.upsertOpportunity(opportunity);
        return opportunity;
      },

      // CT-09 / UI-02: the server answers with the show JSON; a 422
      // (`invalid_email` / `contact_conflict`) propagates to the form.
      async updateLeadEmail(opportunityId, email) {
        const { data } = await ScanSoloPipelineOpportunitiesAPI.updateLeadEmail(
          opportunityId,
          email
        );
        const updated = camelizeOpportunity(data);
        const opportunity = this.opportunities.find(
          o => o.id === opportunityId
        );
        if (opportunity) opportunity.leadEmail = updated.leadEmail;
        return updated;
      },

      // Moves the card immediately (optimistic) so drag-and-drop feels
      // responsive, then reverts it if the server rejects the transition
      // (RF-09) — the card's final resting stage always matches what the
      // server confirmed.
      async transitionStage(opportunityId, targetStage) {
        const opportunity = this.opportunities.find(
          o => o.id === opportunityId
        );
        if (!opportunity) return undefined;

        const previousStage = opportunity.stage;
        opportunity.stage = targetStage;

        try {
          const { data } =
            await ScanSoloPipelineOpportunitiesAPI.stageTransition(
              opportunityId,
              targetStage
            );
          this.upsertOpportunity(camelizeOpportunity(data));
          return this.opportunities.find(o => o.id === opportunityId);
        } catch (error) {
          opportunity.stage = previousStage;
          throw error;
        }
      },
    },
  }
);
