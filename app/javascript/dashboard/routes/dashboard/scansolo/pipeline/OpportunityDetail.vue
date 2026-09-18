<script setup>
import { onMounted, ref } from 'vue';
import camelcaseKeys from 'camelcase-keys';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import ScanSoloPipelineOpportunitiesAPI from 'dashboard/api/scansoloPipelineOpportunities';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const opportunity = ref(null);

// UI-02: contact and conversation come straight off the opportunity payload
// (T13's serializer now embeds contact_name/stage_history for this view);
// no separate fetch is needed.
const fetchOpportunity = async () => {
  const { data } = await ScanSoloPipelineOpportunitiesAPI.show(
    route.params.opportunityId
  );
  opportunity.value = camelcaseKeys(data, { deep: true });
};

const goToConversation = () => {
  if (!opportunity.value) return;

  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: route.params.accountId,
      conversation_id: opportunity.value.conversationId,
    },
  });
};

onMounted(fetchOpportunity);

defineExpose({ fetchOpportunity, goToConversation });
</script>

<template>
  <div v-if="opportunity" class="p-4">
    <h2 class="text-n-slate-12 text-lg font-medium mb-4">
      {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.TITLE') }}
    </h2>

    <section data-testid="opportunity-contact" class="mb-4">
      <h3 class="text-n-slate-11 text-sm font-medium">
        {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.CONTACT_LABEL') }}
      </h3>
      <p data-testid="opportunity-contact-name">
        {{ opportunity.contactName }}
      </p>
    </section>

    <button
      type="button"
      data-testid="opportunity-conversation-link"
      class="mb-4 text-n-blue-text underline"
      @click="goToConversation"
    >
      {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.CONVERSATION_LINK') }}
    </button>

    <section>
      <h3 class="text-n-slate-11 text-sm font-medium mb-2">
        {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.HISTORY_TITLE') }}
      </h3>
      <p
        v-if="!opportunity.stageHistory.length"
        data-testid="opportunity-history-empty"
      >
        {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.HISTORY_EMPTY') }}
      </p>
      <ul v-else data-testid="opportunity-history-list">
        <li
          v-for="event in opportunity.stageHistory"
          :key="event.id"
          data-testid="opportunity-history-item"
        >
          <span data-testid="history-from-stage">{{ event.fromStage }}</span>
          <span data-testid="history-to-stage">{{ event.toStage }}</span>
          <span data-testid="history-created-at">{{ event.createdAt }}</span>
        </li>
      </ul>
    </section>
  </div>
</template>
