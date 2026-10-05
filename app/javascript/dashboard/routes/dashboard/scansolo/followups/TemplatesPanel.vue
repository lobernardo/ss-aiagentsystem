<script setup>
import ScanSoloListState from 'dashboard/routes/dashboard/scansolo/components/ScanSoloListState.vue';
import ScanSoloTime from 'dashboard/routes/dashboard/scansolo/components/ScanSoloTime.vue';
import { onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useScansoloCadenceTemplatesStore } from 'dashboard/store/scansolo/cadenceTemplates';
import { useScanSoloRole } from '../composables/useScanSoloRole';
import { serverErrorMessage } from '../scansoloErrors';
import {
  AVAILABILITY_LABELS,
  META_STATUS_LABELS,
  PARAM_SOURCE_LABELS,
  REASON_LABELS,
  STAGE_LABELS,
  TEMPLATE_SLOT_LABELS,
  enumLabel,
} from '../scansoloLabels';

const STATIC_SOURCE = 'static';

const { t } = useI18n();
const store = useScansoloCadenceTemplatesStore();
const { isAdministrator } = useScanSoloRole();

const loadError = ref(false);
const editingKey = ref(null);
const editForm = reactive({ templateName: '', language: '', params: [] });

const rowKey = row => `${row.stage}:${row.step ?? 'proposal'}`;

const loadRows = async () => {
  loadError.value = false;
  try {
    await store.fetchRows();
  } catch (error) {
    loadError.value = true;
  }
};

onMounted(loadRows);

const stepLabel = row =>
  row.step === null
    ? t('SCANSOLO.FOLLOW_UPS.TEMPLATES.PROPOSAL_SEND')
    : t('SCANSOLO.FOLLOW_UPS.TEMPLATES.STEP_LABEL', { step: row.step });

// CT-09: a single-template slot row reads its own label, not a stage/step.
const rowTitle = row =>
  TEMPLATE_SLOT_LABELS[row.stage]
    ? enumLabel(t, TEMPLATE_SLOT_LABELS, row.stage)
    : `${enumLabel(t, STAGE_LABELS, row.stage)} · ${stepLabel(row)}`;

const paramLabel = param =>
  param.source === STATIC_SOURCE
    ? `"${param.value}"`
    : enumLabel(t, PARAM_SOURCE_LABELS, param.source);

const startEdit = row => {
  editingKey.value = rowKey(row);
  Object.assign(editForm, {
    templateName: row.templateName,
    language: row.language,
    params: row.params.map(param => ({ ...param })),
  });
};

const cancelEdit = () => {
  editingKey.value = null;
};

const addParam = () => {
  editForm.params.push({ source: 'contact_first_name' });
};

const removeParam = index => {
  editForm.params.splice(index, 1);
};

const saveRow = async row => {
  try {
    await store.updateRow({
      stage: row.stage,
      step: row.step,
      templateName: editForm.templateName,
      language: editForm.language,
      params: editForm.params.map(({ source, value }) =>
        source === STATIC_SOURCE ? { source, value } : { source }
      ),
    });
    editingKey.value = null;
    useAlert(t('SCANSOLO.FOLLOW_UPS.TEMPLATES.SAVE_SUCCESS'));
  } catch (error) {
    useAlert(
      serverErrorMessage(error, t('SCANSOLO.FOLLOW_UPS.TEMPLATES.SAVE_ERROR'))
    );
  }
};

defineExpose({ startEdit, saveRow });
</script>

<template>
  <section data-testid="templates-panel" class="mt-8">
    <h2 class="text-base font-medium text-n-slate-12">
      {{ t('SCANSOLO.FOLLOW_UPS.TEMPLATES.TITLE') }}
    </h2>
    <p class="text-sm text-n-slate-11 mb-3">
      {{ t('SCANSOLO.FOLLOW_UPS.TEMPLATES.DESCRIPTION') }}
    </p>

    <ScanSoloListState
      :loading="store.uiFlags.fetchingList"
      :error="loadError"
      :empty="!store.rows.length"
      :empty-message="t('SCANSOLO.FOLLOW_UPS.TEMPLATES.EMPTY_STATE')"
      @retry="loadRows"
    >
      <div
        v-for="row in store.rows"
        :key="rowKey(row)"
        data-testid="template-row"
        :data-row-key="rowKey(row)"
        class="rounded-lg border border-n-weak p-3 mb-2 text-sm"
      >
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0">
            <p data-testid="template-title" class="font-medium text-n-slate-12">
              {{ rowTitle(row) }}
            </p>
            <p class="text-xs text-n-slate-11">
              {{ t('SCANSOLO.FOLLOW_UPS.TEMPLATES.NAME_LABEL') }}:
              <span data-testid="template-name">{{ row.templateName }}</span>
              <span v-if="!row.mapped" class="ms-1 text-n-slate-10">
                ({{ t('SCANSOLO.FOLLOW_UPS.TEMPLATES.CONVENTION') }})
              </span>
              · {{ t('SCANSOLO.FOLLOW_UPS.TEMPLATES.LANGUAGE_LABEL') }}:
              <span data-testid="template-language">{{ row.language }}</span>
            </p>
            <p class="text-xs text-n-slate-11">
              {{ t('SCANSOLO.FOLLOW_UPS.TEMPLATES.PARAMS_LABEL') }}:
              <span data-testid="template-params">
                {{
                  row.params.length
                    ? row.params.map(paramLabel).join(', ')
                    : t('SCANSOLO.FOLLOW_UPS.TEMPLATES.NO_PARAMS')
                }}
              </span>
            </p>
            <p class="text-xs text-n-slate-11">
              {{ t('SCANSOLO.FOLLOW_UPS.TEMPLATES.META_STATUS_LABEL') }}:
              <span data-testid="template-meta-status">
                {{
                  enumLabel(t, META_STATUS_LABELS, row.metaStatus) ||
                  t('SCANSOLO.COMMON.NOT_AVAILABLE')
                }}
              </span>
              · {{ t('SCANSOLO.FOLLOW_UPS.TEMPLATES.LAST_SYNC_LABEL') }}:
              <ScanSoloTime
                data-testid="template-last-sync"
                :value="row.lastSyncedAt"
                :fallback="t('SCANSOLO.FOLLOW_UPS.TEMPLATES.NEVER_SYNCED')"
              />
            </p>
            <p
              v-if="row.blockReason"
              data-testid="template-block-reason"
              class="text-xs text-n-ruby-11"
            >
              {{ t('SCANSOLO.FOLLOW_UPS.TEMPLATES.BLOCK_REASON_LABEL') }}:
              {{ enumLabel(t, REASON_LABELS, row.blockReason) }}
            </p>
          </div>
          <div class="flex items-center gap-2">
            <span
              data-testid="template-availability"
              class="text-xs font-medium px-2 py-1 rounded-full"
              :class="
                row.availability === 'available'
                  ? 'bg-n-teal-3 text-n-teal-11'
                  : 'bg-n-ruby-3 text-n-ruby-11'
              "
            >
              {{ enumLabel(t, AVAILABILITY_LABELS, row.availability) }}
            </span>
            <button
              v-if="isAdministrator && editingKey !== rowKey(row)"
              type="button"
              data-testid="template-edit-button"
              class="rounded-lg border border-n-weak px-3 py-1.5 text-sm"
              @click="startEdit(row)"
            >
              {{ t('SCANSOLO.FOLLOW_UPS.TEMPLATES.EDIT') }}
            </button>
          </div>
        </div>

        <form
          v-if="isAdministrator && editingKey === rowKey(row)"
          data-testid="template-edit-form"
          class="mt-3 grid gap-2"
          @submit.prevent="saveRow(row)"
        >
          <input
            v-model="editForm.templateName"
            type="text"
            data-testid="template-edit-name"
            :aria-label="t('SCANSOLO.FOLLOW_UPS.TEMPLATES.NAME_LABEL')"
            class="rounded-lg border border-n-weak px-3 py-2 text-sm"
          />
          <input
            v-model="editForm.language"
            type="text"
            data-testid="template-edit-language"
            :aria-label="t('SCANSOLO.FOLLOW_UPS.TEMPLATES.LANGUAGE_LABEL')"
            class="rounded-lg border border-n-weak px-3 py-2 text-sm"
          />
          <div
            v-for="(param, index) in editForm.params"
            :key="index"
            data-testid="template-edit-param"
            class="flex gap-2"
          >
            <select
              v-model="param.source"
              :aria-label="
                t('SCANSOLO.FOLLOW_UPS.TEMPLATES.PARAM_SOURCE_LABEL')
              "
              class="rounded-lg border border-n-weak px-3 py-2 text-sm"
            >
              <option
                v-for="(labelKey, source) in PARAM_SOURCE_LABELS"
                :key="source"
                :value="source"
              >
                {{ t(labelKey) }}
              </option>
            </select>
            <input
              v-if="param.source === STATIC_SOURCE"
              v-model="param.value"
              type="text"
              :placeholder="
                t('SCANSOLO.FOLLOW_UPS.TEMPLATES.PARAM_VALUE_PLACEHOLDER')
              "
              class="flex-1 rounded-lg border border-n-weak px-3 py-2 text-sm"
            />
            <button
              type="button"
              class="rounded-lg border border-n-weak px-3 py-1.5 text-sm"
              @click="removeParam(index)"
            >
              {{ t('SCANSOLO.FOLLOW_UPS.TEMPLATES.REMOVE_PARAM') }}
            </button>
          </div>
          <div class="flex gap-2">
            <button
              type="button"
              data-testid="template-add-param"
              class="rounded-lg border border-n-weak px-3 py-1.5 text-sm"
              @click="addParam"
            >
              {{ t('SCANSOLO.FOLLOW_UPS.TEMPLATES.ADD_PARAM') }}
            </button>
            <button
              type="submit"
              data-testid="template-save-button"
              :disabled="store.uiFlags.saving"
              class="rounded-lg bg-n-slate-12 text-n-slate-1 px-3 py-1.5 text-sm disabled:opacity-50"
            >
              {{ t('SCANSOLO.FOLLOW_UPS.TEMPLATES.SAVE') }}
            </button>
            <button
              type="button"
              data-testid="template-cancel-button"
              class="rounded-lg border border-n-weak px-3 py-1.5 text-sm"
              @click="cancelEdit"
            >
              {{ t('SCANSOLO.FOLLOW_UPS.TEMPLATES.CANCEL') }}
            </button>
          </div>
        </form>
      </div>
    </ScanSoloListState>
  </section>
</template>
