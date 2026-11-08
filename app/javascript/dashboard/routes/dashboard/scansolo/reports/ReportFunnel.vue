<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { STAGE_LABELS, enumLabel } from '../scansoloLabels';
import { SCANSOLO_PIPELINE_STAGES } from '../pipeline/pipelineConstants';

// UI-04 / RF-10: the 8 stages in pipeline order, each with active and
// stalled counts at `as_of`.
const props = defineProps({
  funnel: { type: Array, required: true },
});

const { t } = useI18n();

const rows = computed(() =>
  SCANSOLO_PIPELINE_STAGES.map(stage => {
    const row = props.funnel.find(item => item.stage === stage);
    return { stage, active: row?.active ?? 0, stalled: row?.stalled ?? 0 };
  })
);
</script>

<template>
  <section class="flex flex-col gap-2">
    <h2 class="text-base font-medium text-n-slate-12">
      {{ t('SCANSOLO.REPORTS.FUNNEL.TITLE') }}
    </h2>
    <table class="w-full text-sm" data-testid="report-funnel">
      <thead>
        <tr class="text-start text-n-slate-11">
          <th class="py-2 font-medium text-start">
            {{ t('SCANSOLO.REPORTS.FUNNEL.STAGE') }}
          </th>
          <th class="py-2 font-medium text-end">
            {{ t('SCANSOLO.REPORTS.FUNNEL.ACTIVE') }}
          </th>
          <th class="py-2 font-medium text-end">
            {{ t('SCANSOLO.REPORTS.FUNNEL.STALLED') }}
          </th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="row in rows"
          :key="row.stage"
          data-testid="funnel-row"
          :data-stage="row.stage"
          class="border-t border-n-weak"
        >
          <td data-testid="funnel-stage" class="py-2">
            {{ enumLabel(t, STAGE_LABELS, row.stage) }}
          </td>
          <td data-testid="funnel-active" class="py-2 text-end">
            {{ row.active }}
          </td>
          <td data-testid="funnel-stalled" class="py-2 text-end">
            {{ row.stalled }}
          </td>
        </tr>
      </tbody>
    </table>
  </section>
</template>
