<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { storeToRefs } from 'pinia';
import ScanSoloPageLayout from 'dashboard/routes/dashboard/scansolo/components/ScanSoloPageLayout.vue';
import ScanSoloListState from 'dashboard/routes/dashboard/scansolo/components/ScanSoloListState.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import { useScansoloReportsStore } from 'dashboard/store/scansolo/reports';
import {
  ATTEMPT_RESULT_LABELS,
  PROPOSAL_STATUS_LABELS,
  REASON_LABELS,
  TURN_STATUS_LABELS,
  enumLabel,
} from '../scansoloLabels';
import ReportKpiCard from './ReportKpiCard.vue';
import ReportFunnel from './ReportFunnel.vue';
import ReportStalledTable from './ReportStalledTable.vue';
import {
  REPORT_PERIODS,
  formatReportDateTime,
  periodOptions,
} from './reportPeriods';

const SNAPSHOT_SOURCE = 'snapshot';
const LEAD_SOURCES = {
  website: 'SCANSOLO.REPORTS.KPIS.BY_SOURCE.WEBSITE',
  manual: 'SCANSOLO.REPORTS.KPIS.BY_SOURCE.MANUAL',
  nao_informada: 'SCANSOLO.REPORTS.KPIS.BY_SOURCE.NAO_INFORMADA',
};

const { t } = useI18n();
const store = useScansoloReportsStore();
const { report, error, uiFlags } = storeToRefs(store);

// One clock for the whole screen: period options and "days without
// interaction" are computed from the same instant.
const now = new Date();

const tabs = computed(() => [
  { key: REPORT_PERIODS.WEEK, label: t('SCANSOLO.REPORTS.TABS.WEEK') },
  { key: REPORT_PERIODS.MONTH, label: t('SCANSOLO.REPORTS.TABS.MONTH') },
]);

// UI-02: opens on the current week.
const period = ref(REPORT_PERIODS.WEEK);
const anchor = ref(periodOptions(REPORT_PERIODS.WEEK, now)[0].anchor);

const activeTabIndex = computed(() =>
  tabs.value.findIndex(tab => tab.key === period.value)
);

const anchorOptions = computed(() =>
  periodOptions(period.value, now).map(option => ({
    value: option.anchor,
    label: t('SCANSOLO.REPORTS.PERIOD_RANGE', {
      start: option.start,
      end: option.end,
    }),
  }))
);

const onTabChanged = tab => {
  period.value = tab.key;
  anchor.value = periodOptions(tab.key, now)[0].anchor;
};

const loadReport = () =>
  store.fetchReport({ period: period.value, anchor: anchor.value });

watch([period, anchor], loadReport, { immediate: true });

// The store camelizes the whole payload, so enum-keyed maps
// (`by_status.awaiting_approval`) arrive as `awaitingApproval`.
const camelize = value =>
  value.replace(/_([a-z0-9])/g, (_, char) => char.toUpperCase());

const summary = computed(() => report.value.summary);
const previousSummary = computed(() => report.value.previous.summary);

const minutesLabel = value =>
  value === null || value === undefined
    ? t('SCANSOLO.COMMON.NOT_AVAILABLE')
    : t('SCANSOLO.REPORTS.KPIS.MINUTES', { value });

// One breakdown line per enum value of a `{ value: count }` map.
const mapItems = (labels, current, previous) =>
  Object.keys(labels).map(value => ({
    key: value,
    label: enumLabel(t, labels, value),
    value: current[camelize(value)] ?? 0,
    previousValue: previous[camelize(value)] ?? 0,
  }));

const reasonLabel = reason =>
  reason
    ? enumLabel(t, REASON_LABELS, reason)
    : t('SCANSOLO.REPORTS.KPIS.NOT_INFORMED_REASON');

// `[{ ...keys, reason, count }]` lists; the previous count is matched by the
// same keys and is 0 when that reason did not happen before.
const reasonItems = (current, previous, labelFor) =>
  current.map(entry => ({
    key: `${entry.status || ''}:${entry.reason || ''}`,
    label: labelFor(entry),
    value: entry.count,
    previousValue:
      previous.find(
        old => old.status === entry.status && old.reason === entry.reason
      )?.count ?? 0,
  }));

const kpis = computed(() => {
  const current = summary.value;
  const previous = previousSummary.value;
  const cohortHint = t('SCANSOLO.REPORTS.COHORT_HINT');

  return [
    {
      kpi: 'new_leads',
      title: t('SCANSOLO.REPORTS.KPIS.NEW_LEADS'),
      value: current.newLeads.total,
      previousValue: previous.newLeads.total,
      items: mapItems(
        LEAD_SOURCES,
        current.newLeads.bySource,
        previous.newLeads.bySource
      ),
    },
    {
      kpi: 'responded',
      title: t('SCANSOLO.REPORTS.KPIS.RESPONDED'),
      value: current.responded.total,
      previousValue: previous.responded.total,
      hint: cohortHint,
    },
    {
      kpi: 'first_response',
      title: t('SCANSOLO.REPORTS.KPIS.FIRST_RESPONSE'),
      hint: cohortHint,
      items: [
        {
          key: 'median',
          label: t('SCANSOLO.REPORTS.KPIS.MEDIAN'),
          value: minutesLabel(current.firstResponseMinutes.median),
          previousValue: minutesLabel(previous.firstResponseMinutes.median),
        },
        {
          key: 'p90',
          label: t('SCANSOLO.REPORTS.KPIS.P90'),
          value: minutesLabel(current.firstResponseMinutes.p90),
          previousValue: minutesLabel(previous.firstResponseMinutes.p90),
        },
      ],
    },
    {
      kpi: 'qualified',
      title: t('SCANSOLO.REPORTS.KPIS.QUALIFIED'),
      value: current.qualified.total,
      previousValue: previous.qualified.total,
    },
    {
      kpi: 'forwarded',
      title: t('SCANSOLO.REPORTS.KPIS.FORWARDED'),
      value: current.forwarded.total,
      previousValue: previous.forwarded.total,
    },
    {
      kpi: 'ai_turns',
      title: t('SCANSOLO.REPORTS.KPIS.AI_TURNS'),
      items: mapItems(
        TURN_STATUS_LABELS,
        current.aiTurns.byStatus,
        previous.aiTurns.byStatus
      ),
    },
    {
      kpi: 'ai_turn_reasons',
      title: t('SCANSOLO.REPORTS.KPIS.AI_TURN_REASONS'),
      items: reasonItems(
        current.aiTurns.byReason,
        previous.aiTurns.byReason,
        entry =>
          `${enumLabel(t, TURN_STATUS_LABELS, entry.status)} · ${reasonLabel(entry.reason)}`
      ),
    },
    {
      kpi: 'inbound_without_turn',
      title: t('SCANSOLO.REPORTS.KPIS.INBOUND_WITHOUT_TURN'),
      value: current.inboundWithoutTurn.total,
      previousValue: previous.inboundWithoutTurn.total,
    },
    {
      kpi: 'cadence_attempts',
      title: t('SCANSOLO.REPORTS.KPIS.CADENCE_ATTEMPTS'),
      items: mapItems(
        ATTEMPT_RESULT_LABELS,
        current.cadenceAttempts.byResult,
        previous.cadenceAttempts.byResult
      ),
    },
    {
      kpi: 'cadence_block_reasons',
      title: t('SCANSOLO.REPORTS.KPIS.CADENCE_BLOCK_REASONS'),
      items: reasonItems(
        current.cadenceAttempts.byBlockReason,
        previous.cadenceAttempts.byBlockReason,
        entry => reasonLabel(entry.reason)
      ),
    },
    {
      kpi: 'proposals',
      title: t('SCANSOLO.REPORTS.KPIS.PROPOSALS'),
      items: mapItems(
        PROPOSAL_STATUS_LABELS,
        current.proposals.byStatus,
        previous.proposals.byStatus
      ),
    },
  ].filter(card => card.value !== undefined || card.items?.length);
});

const isSnapshot = computed(() => report.value?.source === SNAPSHOT_SOURCE);

// UI-10: "sem dados" = nobody in the pipeline and no new lead in the period.
const isEmpty = computed(
  () =>
    !report.value ||
    (report.value.summary.newLeads.total === 0 &&
      report.value.funnel.every(row => row.active + row.stalled === 0))
);
</script>

<template>
  <ScanSoloPageLayout>
    <div class="flex flex-col gap-6 p-4">
      <div class="flex flex-wrap items-center justify-between gap-4">
        <h1 class="text-xl font-medium text-n-slate-12">
          {{ t('SCANSOLO.REPORTS.TITLE') }}
        </h1>
        <div class="flex flex-wrap items-center gap-3">
          <TabBar
            data-testid="report-tabs"
            :tabs="tabs"
            :initial-active-tab="activeTabIndex"
            @tab-changed="onTabChanged"
          />
          <Select
            v-model="anchor"
            data-testid="report-period-select"
            :options="anchorOptions"
            :aria-label="t('SCANSOLO.REPORTS.PERIOD_LABEL')"
          />
        </div>
      </div>
      <ScanSoloListState
        :loading="uiFlags.fetching"
        :error="Boolean(error)"
        :empty="isEmpty"
        :loading-message="t('SCANSOLO.REPORTS.STATES.LOADING')"
        :error-message="t('SCANSOLO.REPORTS.STATES.ERROR')"
        :empty-message="t('SCANSOLO.REPORTS.STATES.EMPTY')"
        @retry="loadReport"
      >
        <div class="flex flex-col gap-6">
          <p
            v-if="isSnapshot"
            data-testid="report-snapshot-notice"
            class="px-3 py-2 text-sm border rounded-lg border-n-amber-6 bg-n-amber-2 text-n-amber-11"
          >
            {{
              t('SCANSOLO.REPORTS.SNAPSHOT_NOTICE', {
                date: formatReportDateTime(report.generatedAt),
              })
            }}
          </p>
          <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <ReportKpiCard v-for="card in kpis" :key="card.kpi" v-bind="card" />
          </div>
          <ReportFunnel :funnel="report.funnel" />
          <ReportStalledTable :stalled="report.stalled" :now="now" />
        </div>
      </ScanSoloListState>
    </div>
  </ScanSoloPageLayout>
</template>
