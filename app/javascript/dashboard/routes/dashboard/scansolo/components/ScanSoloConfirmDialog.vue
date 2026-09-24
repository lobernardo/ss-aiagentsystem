<script setup>
import { useI18n } from 'vue-i18n';

// UI-09: confirmation shown before a destructive ScanSolo action; the caller
// runs the action only on `confirm`.
defineProps({
  show: { type: Boolean, default: false },
  message: { type: String, required: true },
  confirmLabel: { type: String, default: '' },
  cancelLabel: { type: String, default: '' },
});

defineEmits(['confirm', 'cancel']);

const { t } = useI18n();
</script>

<template>
  <div
    v-if="show"
    data-testid="confirm-dialog"
    class="fixed inset-0 z-50 flex items-center justify-center bg-n-slate-12/40"
  >
    <div class="max-w-sm rounded-lg bg-n-solid-1 p-6" role="alertdialog">
      <p
        data-testid="confirm-dialog-message"
        class="mb-4 text-sm text-n-slate-12"
      >
        {{ message }}
      </p>
      <div class="flex justify-end gap-2">
        <button
          type="button"
          data-testid="confirm-dialog-cancel"
          class="rounded-lg border border-n-weak px-3 py-1.5 text-sm"
          @click="$emit('cancel')"
        >
          {{ cancelLabel || t('SCANSOLO.COMMON.CANCEL') }}
        </button>
        <button
          type="button"
          data-testid="confirm-dialog-confirm"
          class="rounded-lg bg-n-ruby-9 px-3 py-1.5 text-sm text-white"
          @click="$emit('confirm')"
        >
          {{ confirmLabel || t('SCANSOLO.COMMON.CONFIRM') }}
        </button>
      </div>
    </div>
  </div>
</template>
