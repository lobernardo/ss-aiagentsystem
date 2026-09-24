<script setup>
import ScanSoloPageLayout from 'dashboard/routes/dashboard/scansolo/components/ScanSoloPageLayout.vue';
import ScanSoloListState from 'dashboard/routes/dashboard/scansolo/components/ScanSoloListState.vue';
import ScanSoloTime from 'dashboard/routes/dashboard/scansolo/components/ScanSoloTime.vue';
import TechnicalDetails from 'dashboard/routes/dashboard/scansolo/components/TechnicalDetails.vue';
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { storeToRefs } from 'pinia';
import { useStore, useMapGetter } from 'dashboard/composables/store.js';
import { useScansoloPipelineOpportunitiesStore } from 'dashboard/store/scansolo/pipelineOpportunities';
import { STAGE_LABELS, enumLabel } from '../scansoloLabels';
import {
  SCANSOLO_PIPELINE_STAGES,
  SCANSOLO_STALE_THRESHOLD_MS,
} from './pipelineConstants';

const { t } = useI18n();
const store = useScansoloPipelineOpportunitiesStore();
const { opportunities } = storeToRefs(store);
const vuexStore = useStore();
const agents = useMapGetter('agents/getAgents');

const draggedOpportunityId = ref(null);
const loadError = ref(false);

const opportunitiesByStage = computed(() => {
  const groups = Object.fromEntries(
    SCANSOLO_PIPELINE_STAGES.map(stage => [stage, []])
  );
  opportunities.value.forEach(opportunity => {
    (groups[opportunity.stage] ||= []).push(opportunity);
  });
  return groups;
});

const isStale = opportunity => {
  if (!opportunity.lastCustomerInteractionAt) return false;
  const lastInteraction = new Date(
    opportunity.lastCustomerInteractionAt
  ).getTime();
  return Date.now() - lastInteraction >= SCANSOLO_STALE_THRESHOLD_MS;
};

// UI-10: the owner is shown by name; the raw id only in the admin details.
const ownerLabel = opportunity => {
  if (!opportunity.ownerId) {
    return t('SCANSOLO.PIPELINE_BOARD.UNASSIGNED_OWNER');
  }
  const owner = (agents.value || []).find(
    agent => agent.id === opportunity.ownerId
  );
  return owner?.name || t('SCANSOLO.PIPELINE_BOARD.ASSIGNED_OWNER');
};

const cardTechnicalItems = opportunity => [
  { label: t('SCANSOLO.TECHNICAL_DETAILS.ID'), value: opportunity.id },
  {
    label: t('SCANSOLO.TECHNICAL_DETAILS.OWNER_ID'),
    value: opportunity.ownerId,
  },
  {
    label: t('SCANSOLO.TECHNICAL_DETAILS.CONVERSATION_ID'),
    value: opportunity.conversationId,
  },
  {
    label: t('SCANSOLO.TECHNICAL_DETAILS.TIMESTAMP'),
    value: opportunity.lastCustomerInteractionAt,
  },
];

const onDragStart = opportunityId => {
  draggedOpportunityId.value = opportunityId;
};

// A card only ever moves once useScansoloPipelineOpportunitiesStore's
// transitionStage confirms with the server; a 4xx response reverts the
// opportunity's stage in the store, and the card re-renders back into its
// original column (RF-08, RF-09).
const onDrop = async targetStage => {
  const opportunityId = draggedOpportunityId.value;
  draggedOpportunityId.value = null;
  if (!opportunityId) return;

  const opportunity = opportunities.value.find(o => o.id === opportunityId);
  if (!opportunity || opportunity.stage === targetStage) return;

  try {
    await store.transitionStage(opportunityId, targetStage);
  } catch (error) {
    // transitionStage already reverted the local stage; nothing further to do.
  }
};

const loadOpportunities = async () => {
  loadError.value = false;
  try {
    await store.fetchOpportunities();
  } catch (error) {
    loadError.value = true;
  }
};

onMounted(() => {
  vuexStore.dispatch('agents/get');
  loadOpportunities();
});

defineExpose({ onDragStart, onDrop });
</script>

<template>
  <ScanSoloPageLayout>
    <div class="p-4">
      <ScanSoloListState
        :loading="store.uiFlags.fetchingList"
        :error="loadError"
        :empty="!opportunities.length"
        :empty-message="t('SCANSOLO.PIPELINE_BOARD.EMPTY_STATE')"
        @retry="loadOpportunities"
      >
        <div class="flex gap-4 overflow-x-auto" data-testid="pipeline-board">
          <div
            v-for="stage in SCANSOLO_PIPELINE_STAGES"
            :key="stage"
            data-testid="pipeline-column"
            :data-stage="stage"
            class="flex-shrink-0 w-72"
            @dragover.prevent
            @drop="onDrop(stage)"
          >
            <h3 class="text-n-slate-11 text-sm font-medium mb-2">
              {{ enumLabel(t, STAGE_LABELS, stage) }}
            </h3>
            <p
              v-if="!opportunitiesByStage[stage].length"
              class="text-xs text-n-slate-10"
            >
              {{ t('SCANSOLO.PIPELINE_BOARD.EMPTY_COLUMN') }}
            </p>
            <div
              v-for="opportunity in opportunitiesByStage[stage]"
              :key="opportunity.id"
              draggable="true"
              data-testid="pipeline-card"
              :data-opportunity-id="opportunity.id"
              class="rounded-lg border border-n-weak p-3 mb-2 bg-n-solid-1 text-sm"
              @dragstart="onDragStart(opportunity.id)"
            >
              <p class="font-medium text-n-slate-12">
                {{ opportunity.contactName }}
              </p>
              <p data-testid="card-stage" class="text-xs text-n-slate-11">
                {{ enumLabel(t, STAGE_LABELS, stage) }}
              </p>
              <p data-testid="card-owner" class="text-xs text-n-slate-11">
                {{ t('SCANSOLO.PIPELINE_BOARD.OWNER_LABEL') }}:
                {{ ownerLabel(opportunity) }}
              </p>
              <p class="text-xs text-n-slate-11">
                {{ t('SCANSOLO.PIPELINE_BOARD.LAST_INTERACTION_LABEL') }}:
                <ScanSoloTime
                  data-testid="card-last-interaction"
                  :value="opportunity.lastCustomerInteractionAt"
                  :fallback="t('SCANSOLO.COMMON.NOT_AVAILABLE')"
                />
              </p>
              <p class="text-xs text-n-slate-11">
                {{ t('SCANSOLO.PIPELINE_BOARD.NEXT_FOLLOW_UP_LABEL') }}:
                <ScanSoloTime
                  data-testid="card-next-follow-up"
                  :value="opportunity.nextFollowUpAt"
                  :fallback="t('SCANSOLO.PIPELINE_BOARD.NOT_SCHEDULED')"
                />
              </p>
              <p data-testid="card-stale" class="text-xs text-n-amber-11">
                {{
                  isStale(opportunity)
                    ? t('SCANSOLO.PIPELINE_BOARD.STALE_INDICATOR')
                    : ''
                }}
              </p>
              <TechnicalDetails :items="cardTechnicalItems(opportunity)" />
            </div>
          </div>
        </div>
      </ScanSoloListState>
    </div>
  </ScanSoloPageLayout>
</template>
