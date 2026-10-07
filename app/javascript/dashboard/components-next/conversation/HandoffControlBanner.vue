<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import ScanSoloHandoffAPI from 'dashboard/api/scansoloHandoff';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useMapGetter } from 'dashboard/composables/store.js';
import { useScansoloAiAgentConfigStore } from 'dashboard/store/scansolo/aiAgentConfig';
import { MESSAGE_TYPE } from 'shared/constants/messages';

const props = defineProps({
  conversation: { type: Object, required: true },
});

// The implicit takeover (RF-18) runs in an async job after the reply is
// created, so the first read after a human reply can still be `ai_active`.
const IMPLICIT_TAKEOVER_ATTEMPTS = 5;
const IMPLICIT_TAKEOVER_RETRY_MS = 1000;
const TAKEOVER_STATES = ['ai_active'];
const RETURN_STATES = ['human_active', 'awaiting_human'];

const { t } = useI18n();
const { currentAccount } = useAccount();
const { isAdmin } = useAdmin();
const currentUser = useMapGetter('getCurrentUser');
const configStore = useScansoloAiAgentConfigStore();

const controlState = ref(null);
// UI-06: a single `pending` flag gates every action button while a
// takeover/return-to-AI request is in flight, so a repeated click while the
// first request hasn't resolved yet can never fire a second request or
// briefly render an intermediate/duplicate state (no flicker, RF-53).
const pending = ref(false);
const reason = ref('');
const reasonDialog = ref(null);

watch(controlState, state => {
  if (state !== 'ai_active') reasonDialog.value?.close();
});

// UI-01: only ScanSolo accounts, and only inboxes in the published allowlist.
const isScanSoloEnabled = computed(
  () => !!currentAccount.value?.scansolo_enabled
);
const isAllowlisted = computed(() =>
  (configStore.published?.allowedInboxIds || []).includes(
    props.conversation.inbox_id
  )
);
// Mirrors ScanSolo::HandoffPolicy: administrators or the assignee.
const canControl = computed(
  () =>
    isAdmin.value ||
    props.conversation.meta?.assignee?.id === currentUser.value?.id
);

const fetchControlState = async () => {
  const { data } = await ScanSoloHandoffAPI.controlState(props.conversation.id);
  controlState.value = data.ai_control_state;
};

onMounted(async () => {
  if (!isScanSoloEnabled.value) return;
  if (!configStore.draft) await configStore.fetch();
  if (isAllowlisted.value) await fetchControlState();
});

const lastHumanReplyId = computed(
  () =>
    (props.conversation.messages || []).findLast(
      message =>
        message.message_type === MESSAGE_TYPE.OUTGOING &&
        !message.private &&
        message.sender_type === 'User'
    )?.id
);

const refreshAfterHumanReply = async () => {
  for (let attempt = 1; attempt <= IMPLICIT_TAKEOVER_ATTEMPTS; attempt += 1) {
    // eslint-disable-next-line no-await-in-loop
    await fetchControlState();
    if (controlState.value === 'human_active') return;
    // eslint-disable-next-line no-await-in-loop
    await new Promise(resolve => {
      setTimeout(resolve, IMPLICIT_TAKEOVER_RETRY_MS);
    });
  }
};

watch(lastHumanReplyId, () => {
  if (controlState.value) refreshAfterHumanReply();
});

const showTakeover = computed(() =>
  TAKEOVER_STATES.includes(controlState.value)
);
const showReturnToAi = computed(() =>
  RETURN_STATES.includes(controlState.value)
);

const stateLabel = computed(() => {
  if (!controlState.value) return '';
  return t(
    `SCANSOLO.HANDOFF_BANNER.STATES.${controlState.value.toUpperCase()}`
  );
});

const requestTakeover = () => {
  reasonDialog.value.open();
};

const confirmTakeover = async () => {
  if (pending.value) return;

  pending.value = true;
  try {
    await ScanSoloHandoffAPI.takeover(props.conversation.id, reason.value);
    await fetchControlState();
  } catch {
    useAlert(t('SCANSOLO.HANDOFF_BANNER.ERROR'));
  } finally {
    reasonDialog.value?.close();
    pending.value = false;
  }
};

const resetReason = () => {
  reason.value = '';
};

const returnToAi = async () => {
  if (pending.value) return;

  pending.value = true;
  try {
    await ScanSoloHandoffAPI.returnToAi(props.conversation.id);
    await fetchControlState();
  } catch {
    useAlert(t('SCANSOLO.HANDOFF_BANNER.ERROR'));
  } finally {
    reasonDialog.value?.close();
    pending.value = false;
  }
};

defineExpose({ fetchControlState, confirmTakeover, returnToAi });
</script>

<template>
  <div
    v-if="isAllowlisted && controlState"
    data-testid="handoff-control-banner"
    class="flex items-center justify-between gap-3 px-4 py-2 border-b border-n-weak bg-n-solid-1"
  >
    <span data-testid="control-state-label" class="text-sm text-n-slate-12">
      {{ stateLabel }}
    </span>

    <div class="flex items-center gap-2">
      <button
        v-if="showTakeover"
        type="button"
        data-testid="takeover-button"
        :disabled="pending || !canControl"
        :title="canControl ? '' : t('SCANSOLO.HANDOFF_BANNER.NOT_ALLOWED')"
        class="rounded-lg bg-n-slate-12 text-n-slate-1 px-3 py-1.5 text-sm disabled:opacity-50"
        @click="requestTakeover"
      >
        {{ t('SCANSOLO.HANDOFF_BANNER.TAKEOVER_BUTTON') }}
      </button>
      <button
        v-else-if="showReturnToAi"
        type="button"
        data-testid="return-to-ai-button"
        :disabled="pending || !canControl"
        :title="canControl ? '' : t('SCANSOLO.HANDOFF_BANNER.NOT_ALLOWED')"
        class="rounded-lg border border-n-weak px-3 py-1.5 text-sm disabled:opacity-50"
        @click="returnToAi"
      >
        {{ t('SCANSOLO.HANDOFF_BANNER.RETURN_TO_AI_BUTTON') }}
      </button>
    </div>

    <Dialog
      ref="reasonDialog"
      :title="t('SCANSOLO.HANDOFF_BANNER.TAKEOVER_BUTTON')"
      :cancel-button-label="t('SCANSOLO.HANDOFF_BANNER.CANCEL')"
      :confirm-button-label="t('SCANSOLO.HANDOFF_BANNER.TAKEOVER_BUTTON')"
      :is-loading="pending"
      @confirm="confirmTakeover"
      @close="resetReason"
    >
      <label class="block text-sm text-n-slate-11">
        {{ t('SCANSOLO.HANDOFF_BANNER.REASON_LABEL') }}
        <input
          v-model="reason"
          type="text"
          data-testid="takeover-reason-input"
          :placeholder="t('SCANSOLO.HANDOFF_BANNER.REASON_PLACEHOLDER')"
          class="w-full rounded-lg border border-n-weak px-3 py-2 text-sm"
        />
      </label>
    </Dialog>
  </div>
</template>
