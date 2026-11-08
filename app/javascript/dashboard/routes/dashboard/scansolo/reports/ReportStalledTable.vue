<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import {
  COMMERCIAL_STATUS_LABELS,
  STAGE_LABELS,
  STALL_REASON_LABELS,
  SUGGESTED_ACTION_LABELS,
  enumLabel,
} from '../scansoloLabels';
import {
  MS_PER_DAY,
  SCANSOLO_PIPELINE_STAGES,
} from '../pipeline/pipelineConstants';

// UI-05 / RF-10: stalled leads grouped by stage, in pipeline order. Only the
// name, stage, dates and enum labels are shown — never phone, e-mail or
// message content (RNF-01).
const props = defineProps({
  stalled: { type: Array, required: true },
  now: { type: Date, required: true },
});

const { t } = useI18n();
const route = useRoute();

const groups = computed(() =>
  SCANSOLO_PIPELINE_STAGES.map(stage => ({
    stage,
    items: props.stalled.filter(item => item.stage === stage),
  })).filter(group => group.items.length)
);

// RF-04: a lead that never wrote counts from its creation.
const daysWithoutInteraction = item =>
  Math.floor(
    (props.now.getTime() -
      new Date(item.lastCustomerInteractionAt || item.createdAt).getTime()) /
      MS_PER_DAY
  );

const detailRoute = item => ({
  name: 'scansolo_pipeline_opportunity_detail',
  params: {
    accountId: route.params.accountId,
    opportunityId: item.opportunityId,
  },
});
</script>

<template>
  <section class="flex flex-col gap-2">
    <h2 class="text-base font-medium text-n-slate-12">
      {{ t('SCANSOLO.REPORTS.STALLED.TITLE') }}
    </h2>
    <p
      v-if="!groups.length"
      data-testid="stalled-empty"
      class="text-sm text-n-slate-10"
    >
      {{ t('SCANSOLO.REPORTS.STALLED.EMPTY') }}
    </p>
    <div
      v-for="group in groups"
      :key="group.stage"
      data-testid="stalled-group"
      :data-stage="group.stage"
      class="flex flex-col gap-1"
    >
      <h3 class="text-sm font-medium text-n-slate-11">
        {{ enumLabel(t, STAGE_LABELS, group.stage) }}
      </h3>
      <table class="w-full text-sm">
        <thead>
          <tr class="text-n-slate-11">
            <th class="py-2 font-medium text-start">
              {{ t('SCANSOLO.REPORTS.STALLED.LEAD') }}
            </th>
            <th class="py-2 font-medium text-start">
              {{ t('SCANSOLO.REPORTS.STALLED.DAYS_WITHOUT_INTERACTION') }}
            </th>
            <th class="py-2 font-medium text-start">
              {{ t('SCANSOLO.REPORTS.STALLED.COMMERCIAL_STATUS') }}
            </th>
            <th class="py-2 font-medium text-start">
              {{ t('SCANSOLO.REPORTS.STALLED.REASON') }}
            </th>
            <th class="py-2 font-medium text-start">
              {{ t('SCANSOLO.REPORTS.STALLED.SUGGESTED_ACTION') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="item in group.items"
            :key="item.opportunityId"
            data-testid="stalled-row"
            :data-opportunity-id="item.opportunityId"
            class="border-t border-n-weak"
          >
            <td class="py-2">
              <router-link
                data-testid="stalled-lead-link"
                :to="detailRoute(item)"
                class="text-n-blue-11 hover:underline"
              >
                {{ item.contactName }}
              </router-link>
            </td>
            <td data-testid="stalled-days" class="py-2">
              {{
                t(
                  'SCANSOLO.REPORTS.STALLED.DAYS',
                  { count: daysWithoutInteraction(item) },
                  daysWithoutInteraction(item)
                )
              }}
            </td>
            <td data-testid="stalled-commercial-status" class="py-2">
              {{
                enumLabel(t, COMMERCIAL_STATUS_LABELS, item.commercialStatus)
              }}
            </td>
            <td data-testid="stalled-reason" class="py-2">
              {{ enumLabel(t, STALL_REASON_LABELS, item.stallReason) }}
            </td>
            <td data-testid="stalled-action" class="py-2">
              {{ enumLabel(t, SUGGESTED_ACTION_LABELS, item.stallReason) }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>
