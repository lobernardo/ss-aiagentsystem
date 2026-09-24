<script setup>
import ScanSoloPageLayout from 'dashboard/routes/dashboard/scansolo/components/ScanSoloPageLayout.vue';
import ScanSoloListState from 'dashboard/routes/dashboard/scansolo/components/ScanSoloListState.vue';
import ScanSoloTime from 'dashboard/routes/dashboard/scansolo/components/ScanSoloTime.vue';
import TechnicalDetails from 'dashboard/routes/dashboard/scansolo/components/TechnicalDetails.vue';
import { computed, onMounted, ref } from 'vue';
import camelcaseKeys from 'camelcase-keys';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import ScanSoloPipelineOpportunitiesAPI from 'dashboard/api/scansoloPipelineOpportunities';
import { STAGE_LABELS, enumLabel } from '../scansoloLabels';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const opportunity = ref(null);
const loading = ref(false);
const loadError = ref(false);

// UI-02: contact and conversation come straight off the opportunity payload
// (T13's serializer now embeds contact_name/stage_history for this view);
// no separate fetch is needed.
const fetchOpportunity = async () => {
  loading.value = true;
  loadError.value = false;
  try {
    const { data } = await ScanSoloPipelineOpportunitiesAPI.show(
      route.params.opportunityId
    );
    opportunity.value = camelcaseKeys(data, { deep: true });
  } catch (error) {
    loadError.value = true;
  } finally {
    loading.value = false;
  }
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

const stageLabel = stage =>
  stage
    ? enumLabel(t, STAGE_LABELS, stage)
    : t('SCANSOLO.PIPELINE_BOARD.DETAIL.INITIAL_STAGE');

const technicalItems = computed(() => [
  { label: t('SCANSOLO.TECHNICAL_DETAILS.ID'), value: opportunity.value.id },
  {
    label: t('SCANSOLO.TECHNICAL_DETAILS.OWNER_ID'),
    value: opportunity.value.ownerId,
  },
  {
    label: t('SCANSOLO.TECHNICAL_DETAILS.CONTACT_ID'),
    value: opportunity.value.contactId,
  },
  {
    label: t('SCANSOLO.TECHNICAL_DETAILS.CONVERSATION_ID'),
    value: opportunity.value.conversationId,
  },
  {
    label: t('SCANSOLO.TECHNICAL_DETAILS.RAW_PAYLOAD'),
    value: opportunity.value.stageHistory,
  },
]);

onMounted(fetchOpportunity);

defineExpose({ fetchOpportunity, goToConversation });
</script>

<template>
  <ScanSoloPageLayout>
    <div class="p-4">
      <ScanSoloListState
        :loading="loading"
        :error="loadError"
        @retry="fetchOpportunity"
      >
        <div v-if="opportunity">
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
            <p data-testid="opportunity-stage" class="text-sm text-n-slate-11">
              {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.STAGE_LABEL') }}:
              {{ stageLabel(opportunity.stage) }}
            </p>
            <p class="text-sm text-n-slate-11">
              {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.LAST_INTERACTION_LABEL') }}:
              <ScanSoloTime
                :value="opportunity.lastCustomerInteractionAt"
                :fallback="t('SCANSOLO.COMMON.NOT_AVAILABLE')"
              />
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
                class="text-sm"
              >
                <span data-testid="history-from-stage">{{
                  stageLabel(event.fromStage)
                }}</span>
                <span
                  class="i-lucide-arrow-right inline-block size-3 align-middle"
                  aria-hidden="true"
                />
                <span data-testid="history-to-stage">{{
                  stageLabel(event.toStage)
                }}</span>
                ·
                <ScanSoloTime
                  data-testid="history-created-at"
                  :value="event.createdAt"
                />
              </li>
            </ul>
          </section>

          <TechnicalDetails :items="technicalItems" />
        </div>
      </ScanSoloListState>
    </div>
  </ScanSoloPageLayout>
</template>
