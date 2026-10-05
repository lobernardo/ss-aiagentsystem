<script setup>
import ScanSoloPageLayout from 'dashboard/routes/dashboard/scansolo/components/ScanSoloPageLayout.vue';
import ScanSoloListState from 'dashboard/routes/dashboard/scansolo/components/ScanSoloListState.vue';
import ScanSoloConfirmDialog from 'dashboard/routes/dashboard/scansolo/components/ScanSoloConfirmDialog.vue';
import { computed, onBeforeUnmount, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { onBeforeRouteLeave } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useScansoloAiAgentConfigStore } from 'dashboard/store/scansolo/aiAgentConfig';
import { useStore, useMapGetter } from 'dashboard/composables/store.js';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { useScanSoloRole } from '../composables/useScanSoloRole';
import { PROVIDER_LABELS } from '../scansoloLabels';
import { serverErrorMessage } from '../scansoloErrors';
import {
  AGENT_CENTER_FIELD_LABELS,
  AGENT_CENTER_SECTIONS,
  DEFAULT_OPT_OUT_KEYWORDS,
  FIELD_TYPES,
  SELECT_OPTIONS,
  SELECT_PLACEHOLDERS,
} from './agentCenterFields';

// RF-54: same rule the server applies to quote_recipient_email.
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const { t } = useI18n();
const store = useScansoloAiAgentConfigStore();
const vuexStore = useStore();
const inboxes = useMapGetter('inboxes/getInboxes');
const agents = useMapGetter('agents/getAgents');
const { isAdministrator } = useScanSoloRole();

const inboxOptions = computed(() =>
  inboxes.value.map(inbox => ({ value: inbox.id, label: inbox.name }))
);

const selectOptions = computed(() => ({
  [SELECT_OPTIONS.PROVIDERS]: Object.entries(PROVIDER_LABELS).map(
    ([value, labelKey]) => ({ value, label: t(labelKey) })
  ),
  [SELECT_OPTIONS.MODELS]: store.availableModels.map(model => ({
    value: model,
    label: model,
  })),
  [SELECT_OPTIONS.EMAIL_INBOXES]: inboxes.value
    .filter(inbox => inbox.channel_type === INBOX_TYPES.EMAIL)
    .map(inbox => ({ value: inbox.id, label: inbox.name })),
  [SELECT_OPTIONS.AGENTS]: (agents.value || []).map(agent => ({
    value: agent.id,
    label: agent.name,
  })),
}));

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
  allowedInboxIds: [],
  optOutKeywords: [...DEFAULT_OPT_OUT_KEYWORDS],
  quoteInboxId: null,
  commercialUserId: null,
  quoteRecipientEmail: '',
});

const form = reactive(emptyForm());
const savedSnapshot = ref(JSON.stringify(form));
const loadError = ref(false);
const showPublishConfirm = ref(false);
const newKeyword = ref('');
const pendingLeave = ref(null);
const fieldErrors = reactive({ quoteRecipientEmail: '' });

const isDirty = computed(() => JSON.stringify(form) !== savedSnapshot.value);
const isBusy = computed(
  () => store.uiFlags.updatingDraft || store.uiFlags.publishing
);

const applyDraftToForm = draft => {
  if (!draft) return;
  Object.assign(form, emptyForm(), draft);
  savedSnapshot.value = JSON.stringify(form);
};

const loadConfig = async () => {
  loadError.value = false;
  try {
    await store.fetch();
    applyDraftToForm(store.draft);
  } catch (error) {
    loadError.value = true;
  }
};

// UI-06: closing the tab with unsaved draft changes asks the browser to confirm.
const onBeforeUnload = event => {
  if (!isDirty.value) return;
  event.preventDefault();
  event.returnValue = '';
};

onMounted(() => {
  window.addEventListener('beforeunload', onBeforeUnload);
  vuexStore.dispatch('agents/get');
  loadConfig();
});

onBeforeUnmount(() => {
  window.removeEventListener('beforeunload', onBeforeUnload);
});

// UI-06: leaving the route with unsaved draft changes waits for the user.
onBeforeRouteLeave(() => {
  if (!isDirty.value) return true;
  return new Promise(resolve => {
    pendingLeave.value = resolve;
  });
});

const resolveLeave = leave => {
  pendingLeave.value?.(leave);
  pendingLeave.value = null;
};

const hasPublishedVersion = computed(() => !!store.published);

const arrayFieldText = field => (form[field] || []).join('\n');
const onArrayFieldInput = (field, value) => {
  form[field] = value
    .split('\n')
    .map(line => line.trim())
    .filter(Boolean);
};

// UI-14: opt-out keyword list editing.
const addKeyword = () => {
  const keyword = newKeyword.value.trim();
  if (!keyword) return;
  if (!form.optOutKeywords.includes(keyword)) form.optOutKeywords.push(keyword);
  newKeyword.value = '';
};

const removeKeyword = keyword => {
  form.optOutKeywords = form.optOutKeywords.filter(entry => entry !== keyword);
};

const draftPayload = () => ({
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
  allowed_inbox_ids: form.allowedInboxIds,
  opt_out_keywords: form.optOutKeywords,
  quote_inbox_id: form.quoteInboxId,
  commercial_user_id: form.commercialUserId,
  quote_recipient_email: form.quoteRecipientEmail.trim(),
});

const saveDraft = async () => {
  fieldErrors.quoteRecipientEmail = EMAIL_PATTERN.test(
    form.quoteRecipientEmail.trim()
  )
    ? ''
    : t('SCANSOLO.AGENT_CENTER.QUOTE_RECIPIENT_EMAIL_ERROR');
  if (fieldErrors.quoteRecipientEmail) return;

  try {
    const draft = await store.updateDraft(draftPayload());
    applyDraftToForm(draft);
    useAlert(t('SCANSOLO.AGENT_CENTER.SAVE_SUCCESS'));
  } catch (error) {
    useAlert(serverErrorMessage(error, t('SCANSOLO.AGENT_CENTER.SAVE_ERROR')));
  }
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
  showPublishConfirm.value = false;
  try {
    await store.publish();
    useAlert(t('SCANSOLO.AGENT_CENTER.PUBLISH_SUCCESS'));
  } catch (error) {
    useAlert(
      serverErrorMessage(error, t('SCANSOLO.AGENT_CENTER.PUBLISH_ERROR'))
    );
  }
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

      <ScanSoloListState
        :loading="store.uiFlags.fetching"
        :error="loadError"
        @retry="loadConfig"
      >
        <p
          v-if="hasPublishedVersion"
          data-testid="agent-draft-indicator"
          class="text-sm text-n-slate-11 mb-6"
        >
          {{ t('SCANSOLO.AGENT_CENTER.DRAFT_UNPUBLISHED_NOTICE') }}
        </p>
        <p
          v-if="!isAdministrator"
          data-testid="agent-read-only-notice"
          class="text-sm text-n-slate-11 mb-6"
        >
          {{ t('SCANSOLO.AGENT_CENTER.READ_ONLY_NOTICE') }}
        </p>

        <form class="space-y-6" novalidate @submit.prevent="saveDraft">
          <fieldset :disabled="!isAdministrator" class="space-y-6">
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
                  <select
                    v-else-if="field.type === FIELD_TYPES.SELECT"
                    v-model="form[field.name]"
                    :data-testid="`field-${field.name}`"
                    class="w-full rounded-lg border border-n-weak px-3 py-2 text-sm"
                  >
                    <option
                      :value="field.nullable ? null : ''"
                      :disabled="!field.nullable"
                    >
                      {{ t(SELECT_PLACEHOLDERS[field.options]) }}
                    </option>
                    <option
                      v-for="option in selectOptions[field.options]"
                      :key="option.value"
                      :value="option.value"
                    >
                      {{ option.label }}
                    </option>
                  </select>
                  <template v-else-if="field.type === FIELD_TYPES.EMAIL">
                    <input
                      v-model="form[field.name]"
                      type="email"
                      :data-testid="`field-${field.name}`"
                      class="w-full rounded-lg border px-3 py-2 text-sm"
                      :class="
                        fieldErrors[field.name]
                          ? 'border-n-ruby-8'
                          : 'border-n-weak'
                      "
                    />
                    <p
                      v-if="fieldErrors[field.name]"
                      :data-testid="`field-error-${field.name}`"
                      class="mt-1 text-sm text-n-ruby-9"
                    >
                      {{ fieldErrors[field.name] }}
                    </p>
                  </template>
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
                    v-else-if="field.type === FIELD_TYPES.KEYWORDS"
                    :data-testid="`field-${field.name}`"
                  >
                    <p class="text-xs text-n-slate-10 mb-2">
                      {{ t('SCANSOLO.AGENT_CENTER.OPT_OUT_KEYWORDS_HELP') }}
                    </p>
                    <ul class="flex flex-wrap gap-2 mb-2">
                      <li
                        v-for="keyword in form.optOutKeywords"
                        :key="keyword"
                        data-testid="opt-out-keyword"
                        class="flex items-center gap-1 rounded-full bg-n-alpha-2 px-2 py-0.5 text-xs text-n-slate-12"
                      >
                        {{ keyword }}
                        <button
                          v-if="isAdministrator"
                          type="button"
                          data-testid="remove-opt-out-keyword"
                          :aria-label="
                            t('SCANSOLO.AGENT_CENTER.REMOVE_KEYWORD', {
                              keyword,
                            })
                          "
                          class="text-n-slate-10"
                          @click="removeKeyword(keyword)"
                        >
                          <span class="i-lucide-x size-3" aria-hidden="true" />
                        </button>
                      </li>
                    </ul>
                    <div v-if="isAdministrator" class="flex gap-2">
                      <input
                        v-model="newKeyword"
                        type="text"
                        data-testid="new-opt-out-keyword"
                        :placeholder="
                          t('SCANSOLO.AGENT_CENTER.OPT_OUT_KEYWORD_PLACEHOLDER')
                        "
                        class="flex-1 rounded-lg border border-n-weak px-3 py-2 text-sm"
                        @keydown.enter.prevent="addKeyword"
                      />
                      <button
                        type="button"
                        data-testid="add-opt-out-keyword"
                        class="rounded-lg border border-n-weak px-3 py-2 text-sm"
                        @click="addKeyword"
                      >
                        {{ t('SCANSOLO.AGENT_CENTER.ADD_KEYWORD') }}
                      </button>
                    </div>
                  </div>
                  <div
                    v-else-if="field.type === FIELD_TYPES.INBOXES"
                    :data-testid="`field-${field.name}`"
                  >
                    <TagMultiSelectComboBox
                      v-model="form[field.name]"
                      :options="inboxOptions"
                      :placeholder="
                        t('SCANSOLO.AGENT_CENTER.CHANNELS.PLACEHOLDER')
                      "
                      :message="t('SCANSOLO.AGENT_CENTER.CHANNELS.EMPTY_HELP')"
                    />
                  </div>
                </template>
              </div>
            </section>
          </fieldset>

          <div v-if="isAdministrator" class="flex items-center gap-2 pt-2">
            <button
              type="submit"
              data-testid="save-draft-button"
              :disabled="isBusy"
              class="flex items-center gap-2 rounded-lg bg-n-slate-12 text-n-slate-1 px-4 py-2 text-sm disabled:opacity-50 disabled:cursor-not-allowed"
            >
              <Spinner v-if="store.uiFlags.updatingDraft" :size="14" />
              {{ t('SCANSOLO.AGENT_CENTER.SAVE_DRAFT') }}
            </button>
            <button
              type="button"
              data-testid="publish-button"
              :disabled="isBusy"
              class="flex items-center gap-2 rounded-lg border border-n-weak px-4 py-2 text-sm disabled:opacity-50 disabled:cursor-not-allowed"
              @click="requestPublish"
            >
              <Spinner v-if="store.uiFlags.publishing" :size="14" />
              {{ t('SCANSOLO.AGENT_CENTER.PUBLISH') }}
            </button>
          </div>
        </form>
      </ScanSoloListState>

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

      <ScanSoloConfirmDialog
        data-testid="unsaved-changes-dialog"
        :show="!!pendingLeave"
        :message="t('SCANSOLO.AGENT_CENTER.UNSAVED_CHANGES_MESSAGE')"
        :confirm-label="t('SCANSOLO.AGENT_CENTER.LEAVE')"
        :cancel-label="t('SCANSOLO.AGENT_CENTER.STAY')"
        @confirm="resolveLeave(true)"
        @cancel="resolveLeave(false)"
      />
    </div>
  </ScanSoloPageLayout>
</template>
