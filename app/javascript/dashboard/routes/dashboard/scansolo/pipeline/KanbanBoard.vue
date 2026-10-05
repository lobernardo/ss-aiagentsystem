<script setup>
import ScanSoloPageLayout from 'dashboard/routes/dashboard/scansolo/components/ScanSoloPageLayout.vue';
import ScanSoloListState from 'dashboard/routes/dashboard/scansolo/components/ScanSoloListState.vue';
import ScanSoloTime from 'dashboard/routes/dashboard/scansolo/components/ScanSoloTime.vue';
import TechnicalDetails from 'dashboard/routes/dashboard/scansolo/components/TechnicalDetails.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import NewLeadDialog from './NewLeadDialog.vue';
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { storeToRefs } from 'pinia';
import { useStore, useMapGetter } from 'dashboard/composables/store.js';
import { useScansoloPipelineOpportunitiesStore } from 'dashboard/store/scansolo/pipelineOpportunities';
import {
  LEAD_SOURCE_TAGS,
  STAGE_LABELS,
  commercialStatusKey,
  enumLabel,
} from '../scansoloLabels';
import {
  MS_PER_DAY,
  SCANSOLO_PIPELINE_STAGES,
  SCANSOLO_STALE_THRESHOLD_MS,
} from './pipelineConstants';

const AI_ACTIVE = 'ai_active';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useScansoloPipelineOpportunitiesStore();
const { opportunities } = storeToRefs(store);
const vuexStore = useStore();
const agents = useMapGetter('agents/getAgents');

const draggedOpportunityId = ref(null);
const loadError = ref(false);
const newLeadDialogRef = ref(null);

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

// UI-02: whole days since the last customer interaction (or the creation,
// while the customer never replied); shown only from 1 day on.
const daysWithoutInteraction = opportunity => {
  const reference =
    opportunity.lastCustomerInteractionAt || opportunity.createdAt;
  if (!reference) return 0;
  return Math.floor((Date.now() - new Date(reference).getTime()) / MS_PER_DAY);
};

const commercialStatusLabel = opportunity => {
  const key = commercialStatusKey(
    opportunity.quoteRequestStatus,
    opportunity.proposalStatus
  );
  // Keys come from the static maps in scansoloLabels.
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  return key ? t(key) : '';
};

const isHumanAttended = opportunity =>
  (opportunity.aiControlState || AI_ACTIVE) !== AI_ACTIVE;

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

const onDragEnd = () => {
  draggedOpportunityId.value = null;
};

// UI-03: a click opens the lead; finishing a drag never navigates.
const openOpportunity = opportunity => {
  if (draggedOpportunityId.value) return;
  router.push({
    name: 'scansolo_pipeline_opportunity_detail',
    params: {
      accountId: route.params.accountId,
      opportunityId: opportunity.id,
    },
  });
};

const openNewLead = () => {
  newLeadDialogRef.value?.open();
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

defineExpose({ onDragStart, onDrop, openOpportunity });
</script>

<template>
  <ScanSoloPageLayout>
    <div class="p-4">
      <div class="flex items-center justify-end mb-4">
        <Button
          type="button"
          size="sm"
          icon="i-lucide-plus"
          data-testid="new-lead-button"
          :label="t('SCANSOLO.PIPELINE_BOARD.NEW_LEAD.BUTTON')"
          @click="openNewLead"
        />
      </div>
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
              class="rounded-lg border border-n-weak p-3 mb-2 bg-n-solid-1 text-sm cursor-pointer"
              @dragstart="onDragStart(opportunity.id)"
              @dragend="onDragEnd"
              @click="openOpportunity(opportunity)"
            >
              <div class="flex items-center gap-2 mb-1">
                <span
                  v-if="LEAD_SOURCE_TAGS[opportunity.leadSource]"
                  data-testid="card-lead-source"
                  class="text-xs font-medium px-2 py-0.5 rounded-full bg-n-slate-3 text-n-slate-11"
                >
                  {{ enumLabel(t, LEAD_SOURCE_TAGS, opportunity.leadSource) }}
                </span>
                <span
                  v-if="isHumanAttended(opportunity)"
                  data-testid="card-human-attendance"
                  class="text-xs font-medium px-2 py-0.5 rounded-full bg-n-amber-3 text-n-amber-11"
                >
                  {{ t('SCANSOLO.PIPELINE_BOARD.HUMAN_ATTENDANCE') }}
                </span>
              </div>
              <p data-testid="card-title" class="font-medium text-n-slate-12">
                {{ opportunity.company || opportunity.contactName }}
              </p>
              <p
                v-if="opportunity.service"
                data-testid="card-service"
                class="text-xs text-n-slate-11"
              >
                {{ opportunity.service }}
              </p>
              <p
                v-if="opportunity.cityUf"
                data-testid="card-city-uf"
                class="text-xs text-n-slate-11"
              >
                {{ opportunity.cityUf }}
              </p>
              <p
                v-if="commercialStatusLabel(opportunity)"
                data-testid="card-commercial-status"
                class="text-xs font-medium text-n-blue-11"
              >
                {{ commercialStatusLabel(opportunity) }}
              </p>
              <p
                v-if="daysWithoutInteraction(opportunity) >= 1"
                data-testid="card-no-interaction"
                class="text-xs text-n-amber-11"
              >
                {{
                  t('SCANSOLO.PIPELINE_BOARD.NO_INTERACTION_DAYS', {
                    days: daysWithoutInteraction(opportunity),
                  })
                }}
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
              <!-- Expanding the admin details must not open the lead. -->
              <div @click.stop>
                <TechnicalDetails :items="cardTechnicalItems(opportunity)" />
              </div>
            </div>
          </div>
        </div>
      </ScanSoloListState>
    </div>
    <NewLeadDialog ref="newLeadDialogRef" />
  </ScanSoloPageLayout>
</template>
