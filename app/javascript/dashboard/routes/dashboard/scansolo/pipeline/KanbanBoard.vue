<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { storeToRefs } from 'pinia';
import { useScansoloPipelineOpportunitiesStore } from 'dashboard/store/scansolo/pipelineOpportunities';
import {
  SCANSOLO_PIPELINE_STAGES,
  SCANSOLO_STALE_THRESHOLD_MS,
} from './pipelineConstants';

const { t } = useI18n();
const store = useScansoloPipelineOpportunitiesStore();
const { opportunities } = storeToRefs(store);

const draggedOpportunityId = ref(null);

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

onMounted(() => {
  store.fetchOpportunities();
});

defineExpose({ onDragStart, onDrop });
</script>

<template>
  <div class="flex gap-4 overflow-x-auto p-4">
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
        {{ t(`SCANSOLO.PIPELINE_BOARD.STAGES.${stage.toUpperCase()}`) }}
      </h3>
      <div
        v-for="opportunity in opportunitiesByStage[stage]"
        :key="opportunity.id"
        draggable="true"
        data-testid="pipeline-card"
        :data-opportunity-id="opportunity.id"
        class="rounded-lg border border-n-weak p-3 mb-2 bg-n-solid-1"
        @dragstart="onDragStart(opportunity.id)"
      >
        <p data-testid="card-stage">
          {{ t(`SCANSOLO.PIPELINE_BOARD.STAGES.${stage.toUpperCase()}`) }}
        </p>
        <p data-testid="card-owner">
          {{
            opportunity.ownerId || t('SCANSOLO.PIPELINE_BOARD.UNASSIGNED_OWNER')
          }}
        </p>
        <p data-testid="card-last-interaction">
          {{ opportunity.lastCustomerInteractionAt }}
        </p>
        <p data-testid="card-next-follow-up">
          {{
            opportunity.nextFollowUpAt ||
            t('SCANSOLO.PIPELINE_BOARD.NOT_SCHEDULED')
          }}
        </p>
        <p data-testid="card-stale">
          {{
            isStale(opportunity)
              ? t('SCANSOLO.PIPELINE_BOARD.STALE_INDICATOR')
              : ''
          }}
        </p>
      </div>
    </div>
  </div>
</template>
