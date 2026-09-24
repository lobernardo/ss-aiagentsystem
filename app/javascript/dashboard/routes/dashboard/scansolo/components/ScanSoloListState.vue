<script setup>
import { useI18n } from 'vue-i18n';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// UI-09: shared loading / error / empty states for every ScanSolo list.
// The default slot renders only once the list loaded with items.
defineProps({
  loading: { type: Boolean, default: false },
  error: { type: Boolean, default: false },
  empty: { type: Boolean, default: false },
  emptyMessage: { type: String, default: '' },
});

defineEmits(['retry']);

const { t } = useI18n();
</script>

<template>
  <div
    v-if="loading"
    data-testid="list-state-loading"
    class="flex items-center gap-2 py-4 text-sm text-n-slate-11"
  >
    <Spinner :size="16" />
    {{ t('SCANSOLO.COMMON.LOADING') }}
  </div>
  <div
    v-else-if="error"
    data-testid="list-state-error"
    class="flex items-center gap-3 rounded-lg border border-n-ruby-6 bg-n-ruby-2 px-3 py-2 text-sm text-n-ruby-11"
  >
    {{ t('SCANSOLO.COMMON.LOAD_ERROR') }}
    <button
      type="button"
      data-testid="list-state-retry"
      class="underline"
      @click="$emit('retry')"
    >
      {{ t('SCANSOLO.COMMON.RETRY') }}
    </button>
  </div>
  <p
    v-else-if="empty"
    data-testid="list-state-empty"
    class="py-2 text-sm text-n-slate-10"
  >
    {{ emptyMessage || t('SCANSOLO.COMMON.EMPTY') }}
  </p>
  <slot v-else />
</template>
