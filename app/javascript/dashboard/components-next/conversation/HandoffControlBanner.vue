<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ScanSoloHandoffAPI from 'dashboard/api/scansoloHandoff';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});

const { t } = useI18n();

const controlState = ref(null);
// UI-06: a single `pending` flag gates every action button while a
// takeover/return-to-AI request is in flight, so a repeated click while the
// first request hasn't resolved yet can never fire a second request or
// briefly render an intermediate/duplicate state (no flicker, RF-53).
const pending = ref(false);
const reason = ref('');
const showReasonInput = ref(false);

const fetchControlState = async () => {
  const { data } = await ScanSoloHandoffAPI.controlState(props.conversationId);
  controlState.value = data.ai_control_state;
};

onMounted(fetchControlState);

const isAiActive = computed(() => controlState.value === 'ai_active');

const stateLabel = computed(() => {
  if (!controlState.value) return '';
  return t(
    `SCANSOLO.HANDOFF_BANNER.STATES.${controlState.value.toUpperCase()}`
  );
});

const requestTakeover = () => {
  showReasonInput.value = true;
};

const confirmTakeover = async () => {
  if (pending.value) return;

  pending.value = true;
  try {
    const { data } = await ScanSoloHandoffAPI.takeover(
      props.conversationId,
      reason.value
    );
    controlState.value = data.ai_control_state;
    showReasonInput.value = false;
    reason.value = '';
  } finally {
    pending.value = false;
  }
};

const cancelTakeover = () => {
  showReasonInput.value = false;
  reason.value = '';
};

const returnToAi = async () => {
  if (pending.value) return;

  pending.value = true;
  try {
    const { data } = await ScanSoloHandoffAPI.returnToAi(props.conversationId);
    controlState.value = data.ai_control_state;
  } finally {
    pending.value = false;
  }
};

defineExpose({ fetchControlState, confirmTakeover, returnToAi });
</script>

<template>
  <div
    data-testid="handoff-control-banner"
    class="flex items-center justify-between gap-3 px-4 py-2 rounded-lg border border-n-weak bg-n-solid-1"
  >
    <span data-testid="control-state-label" class="text-sm text-n-slate-12">
      {{ stateLabel }}
    </span>

    <div class="flex items-center gap-2">
      <button
        v-if="isAiActive"
        type="button"
        data-testid="takeover-button"
        :disabled="pending"
        class="rounded-lg bg-n-slate-12 text-n-slate-1 px-3 py-1.5 text-sm disabled:opacity-50"
        @click="requestTakeover"
      >
        {{ t('SCANSOLO.HANDOFF_BANNER.TAKEOVER_BUTTON') }}
      </button>
      <button
        v-else
        type="button"
        data-testid="return-to-ai-button"
        :disabled="pending"
        class="rounded-lg border border-n-weak px-3 py-1.5 text-sm disabled:opacity-50"
        @click="returnToAi"
      >
        {{ t('SCANSOLO.HANDOFF_BANNER.RETURN_TO_AI_BUTTON') }}
      </button>
    </div>

    <div
      v-if="showReasonInput"
      data-testid="takeover-reason-dialog"
      class="fixed inset-0 flex items-center justify-center bg-n-slate-12/40"
    >
      <div class="bg-n-solid-1 rounded-lg p-6 max-w-sm w-full">
        <label class="block text-sm text-n-slate-11 mb-1">
          {{ t('SCANSOLO.HANDOFF_BANNER.REASON_LABEL') }}
        </label>
        <input
          v-model="reason"
          type="text"
          data-testid="takeover-reason-input"
          :placeholder="t('SCANSOLO.HANDOFF_BANNER.REASON_PLACEHOLDER')"
          class="w-full rounded-lg border border-n-weak px-3 py-2 text-sm mb-4"
        />
        <div class="flex justify-end gap-2">
          <button
            type="button"
            data-testid="takeover-cancel-button"
            class="rounded-lg border border-n-weak px-3 py-1.5 text-sm"
            @click="cancelTakeover"
          >
            {{ t('SCANSOLO.HANDOFF_BANNER.CANCEL') }}
          </button>
          <button
            type="button"
            data-testid="takeover-confirm-button"
            :disabled="pending"
            class="rounded-lg bg-n-slate-12 text-n-slate-1 px-3 py-1.5 text-sm disabled:opacity-50"
            @click="confirmTakeover"
          >
            {{ t('SCANSOLO.HANDOFF_BANNER.TAKEOVER_BUTTON') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
