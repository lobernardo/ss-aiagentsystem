<script setup>
import { useI18n } from 'vue-i18n';

// UI-03: one KPI with the previous period's value (RF-09). `value` is the
// headline number; `items` are the breakdown lines (origin, status, reason).
defineProps({
  kpi: { type: String, required: true },
  title: { type: String, required: true },
  value: { type: [String, Number], default: null },
  previousValue: { type: [String, Number], default: null },
  hint: { type: String, default: '' },
  items: { type: Array, default: () => [] },
});

const { t } = useI18n();
</script>

<template>
  <div
    data-testid="report-kpi"
    :data-kpi="kpi"
    class="flex flex-col gap-2 p-4 border rounded-lg border-n-weak bg-n-solid-1"
  >
    <h3 class="text-sm font-medium text-n-slate-11">{{ title }}</h3>
    <template v-if="value !== null">
      <p data-testid="report-kpi-value" class="text-2xl font-semibold">
        {{ value }}
      </p>
      <p data-testid="report-kpi-previous" class="text-xs text-n-slate-10">
        {{ t('SCANSOLO.REPORTS.PREVIOUS_VALUE', { value: previousValue }) }}
      </p>
    </template>
    <ul v-if="items.length" class="flex flex-col gap-1">
      <li
        v-for="item in items"
        :key="item.key"
        data-testid="report-kpi-item"
        :data-item="item.key"
        class="flex items-baseline justify-between gap-2 text-sm"
      >
        <span class="text-n-slate-11">{{ item.label }}</span>
        <span class="text-end">
          <span data-testid="report-kpi-item-value" class="font-medium">
            {{ item.value }}
          </span>
          <span
            data-testid="report-kpi-item-previous"
            class="block text-xs text-n-slate-10"
          >
            {{
              t('SCANSOLO.REPORTS.PREVIOUS_VALUE', {
                value: item.previousValue,
              })
            }}
          </span>
        </span>
      </li>
    </ul>
    <p v-if="hint" class="text-xs text-n-slate-10">{{ hint }}</p>
  </div>
</template>
