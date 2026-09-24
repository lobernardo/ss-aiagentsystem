<script setup>
import { useI18n } from 'vue-i18n';
import { useScanSoloRole } from '../composables/useScanSoloRole';

// D-18 / UI-10: technical identifiers (correlation ids, raw ids, ISO
// timestamps, raw JSON) are rendered only for administrators, inside a
// block that starts collapsed.
defineProps({
  // [{ label: translated string, value: string | number | object }]
  items: { type: Array, required: true },
});

const { t } = useI18n();
const { isAdministrator } = useScanSoloRole();

const isStructured = value => value !== null && typeof value === 'object';
</script>

<template>
  <details
    v-if="isAdministrator"
    data-testid="technical-details"
    class="mt-2 rounded-lg border border-n-weak px-3 py-2 text-xs text-n-slate-11"
  >
    <summary class="cursor-pointer font-medium">
      {{ t('SCANSOLO.TECHNICAL_DETAILS.TITLE') }}
    </summary>
    <dl class="mt-2 grid gap-1">
      <div
        v-for="item in items"
        :key="item.label"
        class="grid grid-cols-[minmax(0,10rem)_1fr] gap-2"
      >
        <dt class="text-n-slate-10">{{ item.label }}</dt>
        <dd class="break-all">
          <pre
            v-if="isStructured(item.value)"
            class="whitespace-pre-wrap rounded bg-n-alpha-1 p-2"
            >{{ JSON.stringify(item.value, null, 2) }}</pre
          >
          <template v-else>{{ item.value ?? '' }}</template>
        </dd>
      </div>
    </dl>
  </details>
</template>
