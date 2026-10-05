<script setup>
import ScanSoloListState from 'dashboard/routes/dashboard/scansolo/components/ScanSoloListState.vue';
import ScanSoloConfirmDialog from 'dashboard/routes/dashboard/scansolo/components/ScanSoloConfirmDialog.vue';
import ScanSoloTime from 'dashboard/routes/dashboard/scansolo/components/ScanSoloTime.vue';
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import ScanSoloPipelineOpportunitiesAPI from 'dashboard/api/scansoloPipelineOpportunities';
import { useScansoloQuoteRepliesStore } from 'dashboard/store/scansolo/quoteReplies';
import { useScansoloPipelineOpportunitiesStore } from 'dashboard/store/scansolo/pipelineOpportunities';
import { QUOTE_REPLY_ERROR_LABELS, enumLabel } from '../scansoloLabels';

const UNMATCHED = 'unmatched';
const OPEN_QUOTE_REQUEST_STATUSES = ['awaiting_reply', 'correction_requested'];

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useScansoloQuoteRepliesStore();
const pipelineStore = useScansoloPipelineOpportunitiesStore();

const loadError = ref(false);
// reply id → opportunity id chosen in the "Vincular" select
const selections = reactive({});
const pendingDiscard = ref(null);

// UI-05: a reply can only be linked to an open quote request.
const openQuoteRequestOpportunities = computed(() =>
  pipelineStore.opportunities.filter(opportunity =>
    OPEN_QUOTE_REQUEST_STATUSES.includes(opportunity.quoteRequestStatus)
  )
);

const loadReplies = async () => {
  loadError.value = false;
  try {
    await Promise.all([
      store.fetchPending(),
      pipelineStore.fetchOpportunities(),
    ]);
  } catch (error) {
    loadError.value = true;
  }
};

onMounted(loadReplies);

const optionLabel = opportunity =>
  t('SCANSOLO.PROPOSALS.PENDING_REPLIES.LINK_OPTION', {
    id: opportunity.id,
    name: opportunity.company || opportunity.contactName,
  });

const openConversation = reply => {
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: route.params.accountId,
      conversation_id: reply.conversationId,
    },
  });
};

const runAction = async (action, successKey) => {
  try {
    await action();
    useAlert(t(successKey));
  } catch (error) {
    useAlert(
      enumLabel(t, QUOTE_REPLY_ERROR_LABELS, error?.response?.data?.error) ||
        t('SCANSOLO.COMMON.ACTION_ERROR')
    );
  }
};

// CT-08 takes the quote request id, which only the opportunity show exposes.
const link = reply =>
  runAction(async () => {
    const { data } = await ScanSoloPipelineOpportunitiesAPI.show(
      selections[reply.id]
    );
    await store.link(reply.id, data.quote_request.id);
    delete selections[reply.id];
  }, 'SCANSOLO.PROPOSALS.PENDING_REPLIES.LINK_SUCCESS');

const confirmDiscard = async () => {
  const reply = pendingDiscard.value;
  pendingDiscard.value = null;
  await runAction(
    () => store.discard(reply.id),
    'SCANSOLO.PROPOSALS.PENDING_REPLIES.DISCARD_SUCCESS'
  );
};

defineExpose({ link, confirmDiscard });
</script>

<template>
  <section data-testid="quote-replies-pending" class="mb-6">
    <h2 class="text-base font-medium text-n-slate-12 mb-3">
      {{ t('SCANSOLO.PROPOSALS.PENDING_REPLIES.TITLE') }}
    </h2>

    <ScanSoloListState
      :loading="store.uiFlags.fetchingList"
      :error="loadError"
      :empty="!store.replies.length"
      :empty-message="t('SCANSOLO.PROPOSALS.PENDING_REPLIES.EMPTY_STATE')"
      @retry="loadReplies"
    >
      <div
        v-for="reply in store.replies"
        :key="reply.id"
        data-testid="quote-reply-row"
        :data-reply-id="reply.id"
        :data-kind="reply.kind"
        class="rounded-lg border border-n-weak p-3 mb-2 text-sm"
      >
        <p data-testid="quote-reply-sender" class="text-n-slate-12">
          {{ t('SCANSOLO.PROPOSALS.PENDING_REPLIES.SENDER_LABEL') }}:
          {{ reply.senderEmail }}
        </p>
        <p data-testid="quote-reply-subject" class="text-n-slate-11">
          {{ t('SCANSOLO.PROPOSALS.PENDING_REPLIES.SUBJECT_LABEL') }}:
          {{ reply.subject }}
        </p>
        <p class="text-xs text-n-slate-11">
          {{ t('SCANSOLO.PROPOSALS.PENDING_REPLIES.RECEIVED_AT_LABEL') }}:
          <ScanSoloTime
            data-testid="quote-reply-received-at"
            :value="reply.receivedAt"
          />
        </p>
        <p data-testid="quote-reply-excerpt" class="text-xs text-n-slate-11">
          {{ t('SCANSOLO.PROPOSALS.PENDING_REPLIES.EXCERPT_LABEL') }}:
          {{ reply.excerpt }}
        </p>
        <p
          v-if="reply.kind !== UNMATCHED"
          data-testid="quote-reply-origin"
          class="text-xs font-medium text-n-slate-12"
        >
          {{
            t('SCANSOLO.PROPOSALS.PENDING_REPLIES.ORIGIN_REQUEST', {
              id: reply.quoteRequestId,
            })
          }}
        </p>

        <div class="flex flex-wrap items-center gap-2 mt-2">
          <button
            type="button"
            data-testid="quote-reply-conversation-link"
            class="text-n-blue-text underline"
            @click="openConversation(reply)"
          >
            {{ t('SCANSOLO.PROPOSALS.PENDING_REPLIES.CONVERSATION_LINK') }}
          </button>
          <template v-if="reply.kind === UNMATCHED">
            <select
              v-model="selections[reply.id]"
              data-testid="quote-reply-link-select"
              :aria-label="t('SCANSOLO.PROPOSALS.PENDING_REPLIES.LINK')"
              class="rounded-lg border border-n-weak px-3 py-1.5 text-sm"
            >
              <option :value="undefined" disabled>
                {{ t('SCANSOLO.PROPOSALS.PENDING_REPLIES.LINK_PLACEHOLDER') }}
              </option>
              <option
                v-for="opportunity in openQuoteRequestOpportunities"
                :key="opportunity.id"
                :value="opportunity.id"
              >
                {{ optionLabel(opportunity) }}
              </option>
            </select>
            <button
              type="button"
              data-testid="quote-reply-link-button"
              :disabled="!selections[reply.id]"
              class="rounded-lg border border-n-weak px-3 py-1.5 text-sm disabled:opacity-50 disabled:cursor-not-allowed"
              @click="link(reply)"
            >
              {{ t('SCANSOLO.PROPOSALS.PENDING_REPLIES.LINK') }}
            </button>
          </template>
          <button
            v-else
            type="button"
            data-testid="quote-reply-discard-button"
            class="rounded-lg border border-n-weak px-3 py-1.5 text-sm"
            @click="pendingDiscard = reply"
          >
            {{ t('SCANSOLO.PROPOSALS.PENDING_REPLIES.DISCARD') }}
          </button>
        </div>
      </div>
    </ScanSoloListState>

    <ScanSoloConfirmDialog
      :show="!!pendingDiscard"
      :message="t('SCANSOLO.PROPOSALS.PENDING_REPLIES.DISCARD_CONFIRM_MESSAGE')"
      :confirm-label="t('SCANSOLO.PROPOSALS.PENDING_REPLIES.DISCARD')"
      @confirm="confirmDiscard"
      @cancel="pendingDiscard = null"
    />
  </section>
</template>
