<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useScansoloAiAgentConfigStore } from 'dashboard/store/scansolo/aiAgentConfig';

const { t } = useI18n();
const store = useScansoloAiAgentConfigStore();

const TEXT_FIELDS = [
  'name',
  'modelProvider',
  'modelSelection',
  'role',
  'objective',
  'persona',
  'tone',
  'transferCriteria',
  'responseLimits',
  'serviceHours',
];
const TEXTAREA_FIELDS = ['instructions', 'serviceRules'];
const ARRAY_FIELDS = [
  'qualificationPlaybook',
  'requiredQualificationFields',
  'restrictedInformation',
  'forbiddenSubjects',
];

const emptyForm = () => ({
  name: '',
  enabled: false,
  modelProvider: '',
  modelSelection: '',
  role: '',
  objective: '',
  persona: '',
  tone: '',
  instructions: '',
  serviceRules: '',
  qualificationPlaybook: [],
  requiredQualificationFields: [],
  restrictedInformation: [],
  forbiddenSubjects: [],
  transferCriteria: '',
  responseLimits: '',
  serviceHours: '',
});

const form = reactive(emptyForm());
const showPublishConfirm = ref(false);

const applyDraftToForm = draft => {
  if (!draft) return;
  Object.assign(form, emptyForm(), draft);
};

onMounted(async () => {
  await store.fetch();
  applyDraftToForm(store.draft);
});

const hasPublishedVersion = computed(() => !!store.published);

const arrayFieldText = field => (form[field] || []).join('\n');
const onArrayFieldInput = (field, value) => {
  form[field] = value
    .split('\n')
    .map(line => line.trim())
    .filter(Boolean);
};

const saveDraft = async () => {
  const draft = await store.updateDraft({
    name: form.name,
    enabled: form.enabled,
    model_provider: form.modelProvider,
    model_selection: form.modelSelection,
    role: form.role,
    objective: form.objective,
    persona: form.persona,
    tone: form.tone,
    instructions: form.instructions,
    service_rules: form.serviceRules,
    qualification_playbook: form.qualificationPlaybook,
    required_qualification_fields: form.requiredQualificationFields,
    restricted_information: form.restrictedInformation,
    forbidden_subjects: form.forbiddenSubjects,
    transfer_criteria: form.transferCriteria,
    response_limits: form.responseLimits,
    service_hours: form.serviceHours,
  });
  applyDraftToForm(draft);
};

const requestPublish = () => {
  showPublishConfirm.value = true;
};

const cancelPublish = () => {
  showPublishConfirm.value = false;
};

// UI-03: publish only ever fires from this explicit confirmation step, never
// directly from the "Publicar" button click, so an accidental click on the
// main action never publishes an unreviewed draft.
const confirmPublish = async () => {
  await store.publish();
  showPublishConfirm.value = false;
};

defineExpose({ saveDraft, requestPublish, confirmPublish, cancelPublish });
</script>

<template>
  <div class="p-6 max-w-3xl mx-auto" data-testid="agent-center">
    <div class="flex items-center justify-between mb-4">
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ t('SCANSOLO.AGENT_CENTER.TITLE') }}
      </h1>
      <span
        data-testid="agent-status-indicator"
        class="text-xs font-medium px-2 py-1 rounded-full"
        :class="
          hasPublishedVersion
            ? 'bg-n-teal-3 text-n-teal-11'
            : 'bg-n-amber-3 text-n-amber-11'
        "
      >
        {{
          hasPublishedVersion
            ? t('SCANSOLO.AGENT_CENTER.STATUS_PUBLISHED')
            : t('SCANSOLO.AGENT_CENTER.STATUS_NOT_PUBLISHED')
        }}
      </span>
    </div>

    <p
      v-if="hasPublishedVersion"
      data-testid="agent-draft-indicator"
      class="text-sm text-n-slate-11 mb-6"
    >
      {{ t('SCANSOLO.AGENT_CENTER.DRAFT_UNPUBLISHED_NOTICE') }}
    </p>

    <form class="space-y-4" @submit.prevent="saveDraft">
      <label class="flex items-center gap-2">
        <input
          v-model="form.enabled"
          type="checkbox"
          data-testid="field-enabled"
        />
        {{ t('SCANSOLO.AGENT_CENTER.FIELDS.ENABLED') }}
      </label>

      <div v-for="field in TEXT_FIELDS" :key="field">
        <label class="block text-sm text-n-slate-11 mb-1">
          {{ t(`SCANSOLO.AGENT_CENTER.FIELDS.${field.toUpperCase()}`) }}
        </label>
        <input
          v-model="form[field]"
          type="text"
          :data-testid="`field-${field}`"
          class="w-full rounded-lg border border-n-weak px-3 py-2 text-sm"
        />
      </div>

      <div v-for="field in TEXTAREA_FIELDS" :key="field">
        <label class="block text-sm text-n-slate-11 mb-1">
          {{ t(`SCANSOLO.AGENT_CENTER.FIELDS.${field.toUpperCase()}`) }}
        </label>
        <textarea
          v-model="form[field]"
          rows="3"
          :data-testid="`field-${field}`"
          class="w-full rounded-lg border border-n-weak px-3 py-2 text-sm"
        />
      </div>

      <div v-for="field in ARRAY_FIELDS" :key="field">
        <label class="block text-sm text-n-slate-11 mb-1">
          {{ t(`SCANSOLO.AGENT_CENTER.FIELDS.${field.toUpperCase()}`) }}
        </label>
        <textarea
          :value="arrayFieldText(field)"
          rows="3"
          :data-testid="`field-${field}`"
          class="w-full rounded-lg border border-n-weak px-3 py-2 text-sm"
          @input="onArrayFieldInput(field, $event.target.value)"
        />
      </div>

      <div class="flex gap-2 pt-2">
        <button
          type="submit"
          data-testid="save-draft-button"
          class="rounded-lg bg-n-slate-12 text-n-slate-1 px-4 py-2 text-sm"
        >
          {{ t('SCANSOLO.AGENT_CENTER.SAVE_DRAFT') }}
        </button>
        <button
          type="button"
          data-testid="publish-button"
          class="rounded-lg border border-n-weak px-4 py-2 text-sm"
          @click="requestPublish"
        >
          {{ t('SCANSOLO.AGENT_CENTER.PUBLISH') }}
        </button>
      </div>
    </form>

    <div
      v-if="showPublishConfirm"
      data-testid="publish-confirm-dialog"
      class="fixed inset-0 flex items-center justify-center bg-n-slate-12/40"
    >
      <div class="bg-n-solid-1 rounded-lg p-6 max-w-sm">
        <p class="text-sm text-n-slate-12 mb-4">
          {{ t('SCANSOLO.AGENT_CENTER.PUBLISH_CONFIRM_MESSAGE') }}
        </p>
        <div class="flex justify-end gap-2">
          <button
            type="button"
            data-testid="publish-cancel-button"
            class="rounded-lg border border-n-weak px-3 py-1.5 text-sm"
            @click="cancelPublish"
          >
            {{ t('SCANSOLO.AGENT_CENTER.PUBLISH_CANCEL') }}
          </button>
          <button
            type="button"
            data-testid="publish-confirm-button"
            class="rounded-lg bg-n-ruby-9 text-white px-3 py-1.5 text-sm"
            @click="confirmPublish"
          >
            {{ t('SCANSOLO.AGENT_CENTER.PUBLISH_CONFIRM') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
