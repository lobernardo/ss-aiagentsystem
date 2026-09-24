<script setup>
import ScanSoloPageLayout from 'dashboard/routes/dashboard/scansolo/components/ScanSoloPageLayout.vue';
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useScansoloAiAgentConfigStore } from 'dashboard/store/scansolo/aiAgentConfig';
import { useMapGetter } from 'dashboard/composables/store.js';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import {
  AGENT_CENTER_FIELD_LABELS,
  AGENT_CENTER_SECTIONS,
  FIELD_TYPES,
} from './agentCenterFields';

const { t } = useI18n();
const store = useScansoloAiAgentConfigStore();
const inboxes = useMapGetter('inboxes/getInboxes');

const inboxOptions = computed(() =>
  inboxes.value.map(inbox => ({ value: inbox.id, label: inbox.name }))
);

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
  requireProposalApproval: true,
  allowedInboxIds: [],
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
    require_proposal_approval: form.requireProposalApproval,
    allowed_inbox_ids: form.allowedInboxIds,
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
  <ScanSoloPageLayout>
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

      <form class="space-y-6" @submit.prevent="saveDraft">
        <section
          v-for="section in AGENT_CENTER_SECTIONS"
          :key="section.key"
          :data-testid="`section-${section.key}`"
          class="space-y-4"
        >
          <h2 class="text-base font-medium text-n-slate-12">
            {{ t(section.title) }}
          </h2>
          <div v-for="field in section.fields" :key="field.name">
            <label
              v-if="field.type === FIELD_TYPES.CHECKBOX"
              class="flex items-center gap-2 text-sm text-n-slate-12"
            >
              <input
                v-model="form[field.name]"
                type="checkbox"
                :data-testid="`field-${field.name}`"
              />
              {{ t(AGENT_CENTER_FIELD_LABELS[field.name]) }}
            </label>
            <template v-else>
              <label class="block text-sm text-n-slate-11 mb-1">
                {{ t(AGENT_CENTER_FIELD_LABELS[field.name]) }}
              </label>
              <input
                v-if="field.type === FIELD_TYPES.TEXT"
                v-model="form[field.name]"
                type="text"
                :data-testid="`field-${field.name}`"
                class="w-full rounded-lg border border-n-weak px-3 py-2 text-sm"
              />
              <textarea
                v-else-if="field.type === FIELD_TYPES.TEXTAREA"
                v-model="form[field.name]"
                rows="3"
                :data-testid="`field-${field.name}`"
                class="w-full rounded-lg border border-n-weak px-3 py-2 text-sm"
              />
              <textarea
                v-else-if="field.type === FIELD_TYPES.LIST"
                :value="arrayFieldText(field.name)"
                rows="3"
                :data-testid="`field-${field.name}`"
                class="w-full rounded-lg border border-n-weak px-3 py-2 text-sm"
                @input="onArrayFieldInput(field.name, $event.target.value)"
              />
              <div
                v-else-if="field.type === FIELD_TYPES.INBOXES"
                :data-testid="`field-${field.name}`"
              >
                <TagMultiSelectComboBox
                  v-model="form[field.name]"
                  :options="inboxOptions"
                  :placeholder="t('SCANSOLO.AGENT_CENTER.CHANNELS.PLACEHOLDER')"
                  :message="t('SCANSOLO.AGENT_CENTER.CHANNELS.EMPTY_HELP')"
                />
              </div>
            </template>
          </div>
        </section>

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
  </ScanSoloPageLayout>
</template>
