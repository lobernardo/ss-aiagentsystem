import camelcaseKeys from 'camelcase-keys';
import { defineStore } from 'pinia';
import ScanSoloQuoteRepliesAPI from 'dashboard/api/scansoloQuoteReplies';

const camelizeReply = data => camelcaseKeys(data || {}, { deep: true });

// UI-05: replies pending a manual decision. A reply leaves the list only
// after the server confirms the link/discard (CT-08); a 422 propagates.
export const useScansoloQuoteRepliesStore = defineStore(
  'scansoloQuoteReplies',
  {
    state: () => ({
      replies: [],
      uiFlags: {
        fetchingList: false,
      },
    }),

    actions: {
      removeReply(id) {
        this.replies = this.replies.filter(reply => reply.id !== id);
      },

      async fetchPending() {
        this.uiFlags.fetchingList = true;
        try {
          const { data } = await ScanSoloQuoteRepliesAPI.getPending();
          this.replies = camelizeReply(data);
          return this.replies;
        } finally {
          this.uiFlags.fetchingList = false;
        }
      },

      async link(id, quoteRequestId) {
        const { data } = await ScanSoloQuoteRepliesAPI.link(id, quoteRequestId);
        this.removeReply(id);
        return camelizeReply(data);
      },

      async discard(id) {
        const { data } = await ScanSoloQuoteRepliesAPI.discard(id);
        this.removeReply(id);
        return camelizeReply(data);
      },
    },
  }
);
