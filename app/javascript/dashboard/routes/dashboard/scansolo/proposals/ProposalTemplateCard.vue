<script setup>
import Button from 'dashboard/components-next/button/Button.vue';
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ScanSoloProposalTemplateAPI from 'dashboard/api/scansoloProposalTemplate';
import { useScanSoloRole } from '../composables/useScanSoloRole';
import { PROPOSAL_TEMPLATE_ERROR_LABELS } from '../scansoloLabels';
import { serverErrorMessage } from '../scansoloErrors';

const emit = defineEmits(['uploaded']);

const SHA256_PREFIX_LENGTH = 12;

const { t } = useI18n();
const { isAdministrator } = useScanSoloRole();

const template = ref(null);
const loadError = ref(false);
const selectedFile = ref(null);
const fileInput = ref(null);
const uploading = ref(false);

const loadTemplate = async () => {
  loadError.value = false;
  try {
    const { data } = await ScanSoloProposalTemplateAPI.show();
    template.value = data.template;
  } catch (error) {
    loadError.value = true;
  }
};

onMounted(loadTemplate);

const uploadedAt = computed(() =>
  template.value
    ? new Intl.DateTimeFormat('pt-BR', {
        dateStyle: 'short',
        timeStyle: 'short',
      }).format(new Date(template.value.uploaded_at))
    : ''
);

const onFileChange = event => {
  selectedFile.value = event.target.files?.[0] || null;
};

const errorMessage = error => {
  const { error: code, placeholders } = error?.response?.data || {};
  const key = PROPOSAL_TEMPLATE_ERROR_LABELS[code];
  if (!key) return serverErrorMessage(error, t('SCANSOLO.COMMON.ACTION_ERROR'));

  // Keys come from the static maps in scansoloLabels.
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  const message = t(key);
  return placeholders?.length
    ? `${message}: ${placeholders.join(', ')}`
    : message;
};

const upload = async () => {
  if (!selectedFile.value || uploading.value) return;

  const payload = new FormData();
  payload.append('file', selectedFile.value);
  uploading.value = true;
  try {
    const { data } = await ScanSoloProposalTemplateAPI.upload(payload);
    template.value = data.template;
    selectedFile.value = null;
    if (fileInput.value) fileInput.value.value = '';
    useAlert(t('SCANSOLO.PROPOSALS.TEMPLATE.UPLOAD_SUCCESS'));
    emit('uploaded');
  } catch (error) {
    useAlert(errorMessage(error));
  } finally {
    uploading.value = false;
  }
};
</script>

<template>
  <section
    data-testid="proposal-template-card"
    class="rounded-lg border border-n-weak p-3 mb-4"
  >
    <h2 class="text-sm font-medium text-n-slate-12 mb-2">
      {{ t('SCANSOLO.PROPOSALS.TEMPLATE.TITLE') }}
    </h2>

    <p
      v-if="loadError"
      data-testid="proposal-template-load-error"
      class="text-xs text-n-ruby-11"
    >
      {{ t('SCANSOLO.PROPOSALS.TEMPLATE.LOAD_ERROR') }}
    </p>
    <div
      v-else-if="template"
      data-testid="proposal-template-details"
      class="text-xs text-n-slate-11"
    >
      <p data-testid="proposal-template-filename" class="text-n-slate-12">
        {{ template.filename }}
      </p>
      <p data-testid="proposal-template-uploaded-at">
        {{ t('SCANSOLO.PROPOSALS.TEMPLATE.UPLOADED_AT') }}: {{ uploadedAt }}
      </p>
      <p
        v-if="template.uploaded_by"
        data-testid="proposal-template-uploaded-by"
      >
        {{ t('SCANSOLO.PROPOSALS.TEMPLATE.UPLOADED_BY') }}:
        {{ template.uploaded_by.name }}
      </p>
      <p data-testid="proposal-template-sha256">
        {{ t('SCANSOLO.PROPOSALS.TEMPLATE.SHA256') }}:
        {{ template.sha256.slice(0, SHA256_PREFIX_LENGTH) }}
      </p>
    </div>
    <p
      v-else
      data-testid="proposal-template-none"
      class="text-xs text-n-slate-11"
    >
      {{ t('SCANSOLO.PROPOSALS.TEMPLATE.NONE') }}
    </p>

    <form
      v-if="isAdministrator"
      data-testid="proposal-template-upload-form"
      class="mt-3 flex flex-wrap items-center gap-2"
      @submit.prevent="upload"
    >
      <label class="text-xs text-n-slate-11">
        {{ t('SCANSOLO.PROPOSALS.TEMPLATE.SELECT_FILE') }}
        <input
          ref="fileInput"
          type="file"
          accept=".docx"
          data-testid="proposal-template-file"
          class="ms-2 text-sm"
          @change="onFileChange"
        />
      </label>
      <Button
        type="submit"
        size="sm"
        data-testid="proposal-template-upload"
        :label="t('SCANSOLO.PROPOSALS.TEMPLATE.UPLOAD')"
        :disabled="!selectedFile"
        :is-loading="uploading"
      />
    </form>
  </section>
</template>
