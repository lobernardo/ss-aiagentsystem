import camelcaseKeys from 'camelcase-keys';
import { defineStore } from 'pinia';
import ScanSoloProposalsAPI from 'dashboard/api/scansoloProposals';

const camelizeProposal = data => camelcaseKeys(data || {}, { deep: true });

// UI-08: the Propostas screen reads proposals (and their versions) from
// this store's state only, reflecting whatever the server persisted for
// generate/approve/send within the same request/response cycle.
export const useScansoloProposalsStore = defineStore('scansoloProposals', {
  state: () => ({
    proposals: [],
    uiFlags: {
      fetchingList: false,
    },
  }),

  actions: {
    upsertProposal(proposal) {
      const index = this.proposals.findIndex(p => p.id === proposal.id);
      if (index === -1) {
        this.proposals.push(proposal);
      } else {
        this.proposals[index] = proposal;
      }
    },

    upsertVersion(proposalId, version) {
      const proposal = this.proposals.find(p => p.id === proposalId);
      if (!proposal) return;

      const index = proposal.versions.findIndex(v => v.id === version.id);
      if (index === -1) {
        proposal.versions.push(version);
      } else {
        proposal.versions[index] = version;
      }

      if (version.isCurrent) {
        proposal.currentVersionId = version.id;
        proposal.versions.forEach(v => {
          if (v.id !== version.id) v.isCurrent = false;
        });
      }
    },

    async fetchProposals() {
      this.uiFlags.fetchingList = true;
      try {
        const { data } = await ScanSoloProposalsAPI.get();
        this.proposals = camelizeProposal(data);
        return this.proposals;
      } finally {
        this.uiFlags.fetchingList = false;
      }
    },

    async generateProposal(opportunityId, correlationId) {
      const { data } = await ScanSoloProposalsAPI.generate(
        opportunityId,
        correlationId
      );
      await this.fetchProposals();
      return camelizeProposal(data);
    },

    async approveProposal(proposalId, proposalVersionId, correlationId) {
      const { data } = await ScanSoloProposalsAPI.approve(
        proposalId,
        proposalVersionId,
        correlationId
      );
      this.upsertVersion(proposalId, camelizeProposal(data));
      return camelizeProposal(data);
    },

    async sendProposal(proposalId, proposalVersionId, correlationId) {
      const { data } = await ScanSoloProposalsAPI.send(
        proposalId,
        proposalVersionId,
        correlationId
      );
      this.upsertVersion(proposalId, camelizeProposal(data));
      return camelizeProposal(data);
    },
  },
});
