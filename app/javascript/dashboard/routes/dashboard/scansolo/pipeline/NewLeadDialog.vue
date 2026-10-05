<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store.js';
import { useScansoloPipelineOpportunitiesStore } from 'dashboard/store/scansolo/pipelineOpportunities';
import { useScansoloAiAgentConfigStore } from 'dashboard/store/scansolo/aiAgentConfig';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { MANUAL_LEAD_ERROR_LABELS, enumLabel } from '../scansoloLabels';
import { E164_PHONE_PATTERN } from './pipelineConstants';

const emit = defineEmits(['close']);

const OPPORTUNITY_EXISTS = 'opportunity_exists';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useScansoloPipelineOpportunitiesStore();
const configStore = useScansoloAiAgentConfigStore();
const agents = useMapGetter('agents/getAgents');
const inboxes = useMapGetter('inboxes/getInboxes');

const dialogRef = ref(null);
const isSaving = ref(false);
const serverError = ref(null);
const fieldErrors = reactive({ name: '', phoneNumber: '', inboxId: '' });

const emptyForm = () => ({
  name: '',
  phoneNumber: '',
  email: '',
  company: '',
  ownerId: '',
  inboxId: '',
});
const form = reactive(emptyForm());

// UI-01: only WhatsApp inboxes of the published allowlist can start a lead.
const whatsappInboxes = computed(() => {
  const allowed = configStore.published?.allowedInboxIds || [];
  return (inboxes.value || []).filter(
    inbox =>
      inbox.channel_type === INBOX_TYPES.WHATSAPP && allowed.includes(inbox.id)
  );
});

const resetForm = () => {
  Object.assign(form, emptyForm());
  Object.assign(fieldErrors, { name: '', phoneNumber: '', inboxId: '' });
  serverError.value = null;
};

// UI-01: with exactly one allowlisted WhatsApp inbox it comes pre-selected.
const preselectInbox = () => {
  if (whatsappInboxes.value.length === 1) {
    form.inboxId = whatsappInboxes.value[0].id;
  }
};

const open = async () => {
  resetForm();
  dialogRef.value?.open();
  try {
    await configStore.fetch();
  } catch (error) {
    // Without the published config no inbox is offered; CT-01 answers
    // `invalid_inbox` and the form shows it.
  }
  preselectInbox();
};

const close = () => {
  dialogRef.value?.close();
};

const validate = () => {
  fieldErrors.name = form.name.trim()
    ? ''
    : t('SCANSOLO.PIPELINE_BOARD.NEW_LEAD.ERRORS.MISSING_NAME');
  fieldErrors.phoneNumber = E164_PHONE_PATTERN.test(form.phoneNumber.trim())
    ? ''
    : t('SCANSOLO.PIPELINE_BOARD.NEW_LEAD.ERRORS.INVALID_PHONE');
  fieldErrors.inboxId =
    whatsappInboxes.value.length > 1 && !form.inboxId
      ? t('SCANSOLO.PIPELINE_BOARD.NEW_LEAD.ERRORS.INVALID_INBOX')
      : '';
  return !fieldErrors.name && !fieldErrors.phoneNumber && !fieldErrors.inboxId;
};

const payload = () => ({
  name: form.name.trim(),
  phone_number: form.phoneNumber.trim(),
  email: form.email.trim() || undefined,
  company: form.company.trim() || undefined,
  owner_id: form.ownerId || undefined,
  inbox_id: form.inboxId || undefined,
});

const submit = async () => {
  serverError.value = null;
  if (!validate()) return;

  isSaving.value = true;
  try {
    await store.createOpportunity(payload());
    useAlert(t('SCANSOLO.PIPELINE_BOARD.NEW_LEAD.SUCCESS'));
    close();
  } catch (error) {
    const data = error?.response?.data || {};
    serverError.value = {
      code: data.error,
      opportunityId: data.opportunity_id,
    };
  } finally {
    isSaving.value = false;
  }
};

const serverErrorMessage = computed(() => {
  if (!serverError.value) return '';
  return (
    enumLabel(t, MANUAL_LEAD_ERROR_LABELS, serverError.value.code) ||
    t('SCANSOLO.COMMON.ACTION_ERROR')
  );
});

const canOpenExisting = computed(
  () =>
    serverError.value?.code === OPPORTUNITY_EXISTS &&
    !!serverError.value.opportunityId
);

const openExisting = () => {
  router.push({
    name: 'scansolo_pipeline_opportunity_detail',
    params: {
      accountId: route.params.accountId,
      opportunityId: serverError.value.opportunityId,
    },
  });
  close();
};

defineExpose({ open, close, submit });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('SCANSOLO.PIPELINE_BOARD.NEW_LEAD.TITLE')"
    :confirm-button-label="t('SCANSOLO.PIPELINE_BOARD.NEW_LEAD.SAVE')"
    :cancel-button-label="t('SCANSOLO.PIPELINE_BOARD.NEW_LEAD.CANCEL')"
    :is-loading="isSaving"
    overflow-y-auto
    @confirm="submit"
    @close="emit('close')"
  >
    <div class="flex flex-col gap-4" data-testid="new-lead-form">
      <Input
        v-model="form.name"
        data-testid="new-lead-name"
        :label="t('SCANSOLO.PIPELINE_BOARD.NEW_LEAD.FIELDS.NAME')"
        :placeholder="t('SCANSOLO.PIPELINE_BOARD.NEW_LEAD.PLACEHOLDERS.NAME')"
        :message="fieldErrors.name"
        :message-type="fieldErrors.name ? 'error' : 'info'"
      />
      <Input
        v-model="form.phoneNumber"
        data-testid="new-lead-phone"
        type="tel"
        :label="t('SCANSOLO.PIPELINE_BOARD.NEW_LEAD.FIELDS.PHONE')"
        :placeholder="t('SCANSOLO.PIPELINE_BOARD.NEW_LEAD.PLACEHOLDERS.PHONE')"
        :message="fieldErrors.phoneNumber"
        :message-type="fieldErrors.phoneNumber ? 'error' : 'info'"
      />
      <Input
        v-model="form.email"
        data-testid="new-lead-email"
        type="email"
        :label="t('SCANSOLO.PIPELINE_BOARD.NEW_LEAD.FIELDS.EMAIL')"
        :placeholder="t('SCANSOLO.PIPELINE_BOARD.NEW_LEAD.PLACEHOLDERS.EMAIL')"
      />
      <Input
        v-model="form.company"
        data-testid="new-lead-company"
        :label="t('SCANSOLO.PIPELINE_BOARD.NEW_LEAD.FIELDS.COMPANY')"
        :placeholder="
          t('SCANSOLO.PIPELINE_BOARD.NEW_LEAD.PLACEHOLDERS.COMPANY')
        "
      />
      <label class="flex flex-col gap-1 text-heading-3 text-n-slate-12">
        {{ t('SCANSOLO.PIPELINE_BOARD.NEW_LEAD.FIELDS.OWNER') }}
        <select
          v-model="form.ownerId"
          data-testid="new-lead-owner"
          class="w-full rounded-lg border border-n-weak px-3 py-2 text-sm"
        >
          <option value="">
            {{ t('SCANSOLO.PIPELINE_BOARD.NEW_LEAD.PLACEHOLDERS.OWNER') }}
          </option>
          <option v-for="agent in agents" :key="agent.id" :value="agent.id">
            {{ agent.name }}
          </option>
        </select>
      </label>
      <label class="flex flex-col gap-1 text-heading-3 text-n-slate-12">
        {{ t('SCANSOLO.PIPELINE_BOARD.NEW_LEAD.FIELDS.INBOX') }}
        <select
          v-model="form.inboxId"
          data-testid="new-lead-inbox"
          class="w-full rounded-lg border border-n-weak px-3 py-2 text-sm"
        >
          <option value="" disabled>
            {{ t('SCANSOLO.PIPELINE_BOARD.NEW_LEAD.PLACEHOLDERS.INBOX') }}
          </option>
          <option
            v-for="inbox in whatsappInboxes"
            :key="inbox.id"
            :value="inbox.id"
          >
            {{ inbox.name }}
          </option>
        </select>
        <span
          v-if="fieldErrors.inboxId"
          data-testid="new-lead-inbox-error"
          class="text-sm text-n-ruby-9"
        >
          {{ fieldErrors.inboxId }}
        </span>
      </label>
      <div
        v-if="serverError"
        data-testid="new-lead-server-error"
        class="flex flex-col gap-2 rounded-lg border border-n-ruby-6 bg-n-ruby-2 px-3 py-2 text-sm text-n-ruby-11"
      >
        <p>{{ serverErrorMessage }}</p>
        <Button
          v-if="canOpenExisting"
          type="button"
          size="sm"
          variant="link"
          data-testid="new-lead-open-existing"
          :label="t('SCANSOLO.PIPELINE_BOARD.NEW_LEAD.OPEN_EXISTING')"
          @click="openExisting"
        />
      </div>
    </div>
  </Dialog>
</template>
