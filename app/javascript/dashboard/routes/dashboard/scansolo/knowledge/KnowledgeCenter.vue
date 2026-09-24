<script setup>
import ScanSoloPageLayout from 'dashboard/routes/dashboard/scansolo/components/ScanSoloPageLayout.vue';
import ScanSoloListState from 'dashboard/routes/dashboard/scansolo/components/ScanSoloListState.vue';
import ScanSoloConfirmDialog from 'dashboard/routes/dashboard/scansolo/components/ScanSoloConfirmDialog.vue';
import ScanSoloTime from 'dashboard/routes/dashboard/scansolo/components/ScanSoloTime.vue';
import TechnicalDetails from 'dashboard/routes/dashboard/scansolo/components/TechnicalDetails.vue';
import { onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useScansoloKnowledgeStore } from 'dashboard/store/scansolo/knowledgeSources';
import { useScanSoloRole } from '../composables/useScanSoloRole';
import { INDEX_STATUS_LABELS, enumLabel } from '../scansoloLabels';
import { serverErrorMessage } from '../scansoloErrors';

const { t } = useI18n();
const store = useScansoloKnowledgeStore();
const { isAdministrator } = useScanSoloRole();

const SOURCE_TYPES = ['document', 'faq', 'company_info'];
// RNF-06: the server rejects a retrieval test above this top_k.
const MAX_TOP_K = 20;

const STATUS_BADGE_CLASSES = {
  pending: 'bg-n-slate-3 text-n-slate-11',
  indexing: 'bg-n-blue-3 text-n-blue-11',
  indexed: 'bg-n-teal-3 text-n-teal-11',
  failed: 'bg-n-ruby-3 text-n-ruby-11',
};

const emptyForm = () => ({
  sourceType: 'faq',
  title: '',
  content: '',
  origin: '',
  file: null,
});

const form = reactive(emptyForm());
const queryForm = reactive({ query: '', topK: 5 });
const fileInput = ref(null);
const loadError = ref(false);
const sourcePendingDelete = ref(null);

const loadSources = async () => {
  loadError.value = false;
  try {
    await store.fetchSources();
  } catch (error) {
    loadError.value = true;
  }
};

onMounted(loadSources);

// UI-09: every mutation ends in a toast with the server's own message on failure.
const runMutation = async (mutation, successKey) => {
  try {
    await mutation();
    useAlert(t(successKey));
    return true;
  } catch (error) {
    useAlert(serverErrorMessage(error, t('SCANSOLO.COMMON.ACTION_ERROR')));
    return false;
  }
};

const onFileChange = event => {
  form.file = event.target.files?.[0] || null;
};

const addSource = async () => {
  const payload = new FormData();
  payload.append('source_type', form.sourceType);
  payload.append('title', form.title);
  payload.append('content', form.content);
  payload.append('origin', form.origin);
  if (form.file) payload.append('file', form.file);

  const created = await runMutation(
    () => store.createSource(payload),
    'SCANSOLO.KNOWLEDGE_CENTER.CREATE_SUCCESS'
  );
  if (!created) return;

  Object.assign(form, emptyForm());
  if (fileInput.value) fileInput.value.value = '';
};

const toggleEnabled = source =>
  runMutation(
    () => store.toggleEnabled(source.id, !source.enabled),
    'SCANSOLO.KNOWLEDGE_CENTER.UPDATE_SUCCESS'
  );

const reindex = source =>
  runMutation(
    () => store.reindexSource(source.id),
    'SCANSOLO.KNOWLEDGE_CENTER.REINDEX_SUCCESS'
  );

// UI-09: deleting a source always goes through the confirmation first.
const removeSource = source => {
  sourcePendingDelete.value = source;
};

const confirmRemoveSource = async () => {
  const source = sourcePendingDelete.value;
  sourcePendingDelete.value = null;
  await runMutation(
    () => store.deleteSource(source.id),
    'SCANSOLO.KNOWLEDGE_CENTER.DELETE_SUCCESS'
  );
};

const runRetrievalTest = async () => {
  try {
    await store.runRetrievalTest(queryForm.query, queryForm.topK);
  } catch (error) {
    useAlert(serverErrorMessage(error, t('SCANSOLO.COMMON.ACTION_ERROR')));
  }
};

const sourceTitle = sourceId =>
  store.sources.find(source => source.id === sourceId)?.title ||
  t('SCANSOLO.TURN_EVIDENCE_VIEWER.UNTITLED_SOURCE');

const sourceTechnicalItems = source => [
  { label: t('SCANSOLO.TECHNICAL_DETAILS.SOURCE_ID'), value: source.id },
  {
    label: t('SCANSOLO.TECHNICAL_DETAILS.TIMESTAMP'),
    value: source.indexedAt,
  },
];

const resultTechnicalItems = result => [
  { label: t('SCANSOLO.TECHNICAL_DETAILS.SOURCE_ID'), value: result.sourceId },
  { label: t('SCANSOLO.TECHNICAL_DETAILS.CHUNK_ID'), value: result.chunkId },
];

defineExpose({
  addSource,
  toggleEnabled,
  reindex,
  removeSource,
  runRetrievalTest,
});
</script>

<template>
  <ScanSoloPageLayout>
    <div class="p-6 max-w-4xl mx-auto" data-testid="knowledge-center">
      <h1 class="text-xl font-medium text-n-slate-12 mb-4">
        {{ t('SCANSOLO.KNOWLEDGE_CENTER.TITLE') }}
      </h1>

      <p
        v-if="!isAdministrator"
        data-testid="knowledge-read-only-notice"
        class="text-sm text-n-slate-11 mb-6"
      >
        {{ t('SCANSOLO.KNOWLEDGE_CENTER.READ_ONLY_NOTICE') }}
      </p>

      <section v-if="isAdministrator" class="mb-8">
        <h2 class="text-sm font-medium text-n-slate-11 mb-2">
          {{ t('SCANSOLO.KNOWLEDGE_CENTER.ADD_SOURCE_TITLE') }}
        </h2>
        <form
          class="grid gap-3 rounded-lg border border-n-weak p-4"
          @submit.prevent="addSource"
        >
          <select
            v-model="form.sourceType"
            data-testid="field-source-type"
            class="rounded-lg border border-n-weak px-3 py-2 text-sm"
          >
            <option v-for="type in SOURCE_TYPES" :key="type" :value="type">
              {{
                t(
                  `SCANSOLO.KNOWLEDGE_CENTER.SOURCE_TYPES.${type.toUpperCase()}`
                )
              }}
            </option>
          </select>
          <input
            v-model="form.title"
            type="text"
            data-testid="field-title"
            :placeholder="t('SCANSOLO.KNOWLEDGE_CENTER.FIELDS.TITLE')"
            class="rounded-lg border border-n-weak px-3 py-2 text-sm"
          />
          <textarea
            v-model="form.content"
            data-testid="field-content"
            rows="3"
            :placeholder="t('SCANSOLO.KNOWLEDGE_CENTER.FIELDS.CONTENT')"
            class="rounded-lg border border-n-weak px-3 py-2 text-sm"
          />
          <input
            v-model="form.origin"
            type="text"
            data-testid="field-origin"
            :placeholder="t('SCANSOLO.KNOWLEDGE_CENTER.FIELDS.ORIGIN')"
            class="rounded-lg border border-n-weak px-3 py-2 text-sm"
          />
          <input
            ref="fileInput"
            type="file"
            data-testid="field-file"
            class="text-sm"
            @change="onFileChange"
          />
          <button
            type="submit"
            data-testid="add-source-button"
            :disabled="store.uiFlags.creating"
            class="rounded-lg bg-n-slate-12 text-n-slate-1 px-4 py-2 text-sm w-fit disabled:opacity-50"
          >
            {{ t('SCANSOLO.KNOWLEDGE_CENTER.ADD_SOURCE') }}
          </button>
        </form>
      </section>

      <section class="mb-8">
        <h2 class="text-sm font-medium text-n-slate-11 mb-2">
          {{ t('SCANSOLO.KNOWLEDGE_CENTER.SOURCES_TITLE') }}
        </h2>
        <ScanSoloListState
          :loading="store.uiFlags.fetchingList"
          :error="loadError"
          :empty="!store.sources.length"
          :empty-message="t('SCANSOLO.KNOWLEDGE_CENTER.EMPTY_STATE')"
          @retry="loadSources"
        >
          <div
            v-for="source in store.sources"
            :key="source.id"
            data-testid="source-row"
            :data-source-id="source.id"
            class="rounded-lg border border-n-weak p-3 mb-2"
          >
            <div class="flex items-center justify-between gap-3">
              <div class="min-w-0">
                <p data-testid="source-title" class="text-sm font-medium">
                  {{ source.title }}
                </p>
                <p class="text-xs text-n-slate-10">
                  {{
                    t(
                      `SCANSOLO.KNOWLEDGE_CENTER.SOURCE_TYPES.${source.sourceType?.toUpperCase()}`
                    )
                  }}
                  · {{ t('SCANSOLO.KNOWLEDGE_CENTER.CHUNK_COUNT_LABEL') }}:
                  <span data-testid="source-chunk-count">{{
                    source.chunkCount
                  }}</span>
                  · {{ t('SCANSOLO.KNOWLEDGE_CENTER.INDEXED_AT_LABEL') }}:
                  <ScanSoloTime
                    data-testid="source-indexed-at"
                    :value="source.indexedAt"
                    :fallback="t('SCANSOLO.KNOWLEDGE_CENTER.NOT_INDEXED')"
                  />
                </p>
              </div>
              <div class="flex flex-wrap items-center justify-end gap-2">
                <span
                  data-testid="source-index-status"
                  class="text-xs font-medium px-2 py-1 rounded-full"
                  :class="STATUS_BADGE_CLASSES[source.indexStatus]"
                >
                  {{ enumLabel(t, INDEX_STATUS_LABELS, source.indexStatus) }}
                </span>
                <span
                  data-testid="source-enabled-indicator"
                  class="text-xs font-medium px-2 py-1 rounded-full"
                  :class="
                    source.enabled
                      ? 'bg-n-teal-3 text-n-teal-11'
                      : 'bg-n-amber-3 text-n-amber-11'
                  "
                >
                  {{
                    source.enabled
                      ? t('SCANSOLO.KNOWLEDGE_CENTER.ENABLED')
                      : t('SCANSOLO.KNOWLEDGE_CENTER.DISABLED')
                  }}
                </span>
                <template v-if="isAdministrator">
                  <button
                    type="button"
                    data-testid="toggle-enabled-button"
                    class="rounded-lg border border-n-weak px-3 py-1.5 text-sm"
                    @click="toggleEnabled(source)"
                  >
                    {{
                      source.enabled
                        ? t('SCANSOLO.KNOWLEDGE_CENTER.DISABLE')
                        : t('SCANSOLO.KNOWLEDGE_CENTER.ENABLE')
                    }}
                  </button>
                  <button
                    type="button"
                    data-testid="reindex-button"
                    class="rounded-lg border border-n-weak px-3 py-1.5 text-sm"
                    @click="reindex(source)"
                  >
                    {{ t('SCANSOLO.KNOWLEDGE_CENTER.REINDEX') }}
                  </button>
                  <button
                    type="button"
                    data-testid="delete-source-button"
                    class="rounded-lg border border-n-ruby-9 text-n-ruby-9 px-3 py-1.5 text-sm"
                    @click="removeSource(source)"
                  >
                    {{ t('SCANSOLO.KNOWLEDGE_CENTER.DELETE') }}
                  </button>
                </template>
              </div>
            </div>
            <p
              v-if="source.indexStatus === 'failed' && source.indexError"
              data-testid="source-index-error"
              class="mt-2 text-xs text-n-ruby-11"
            >
              {{ t('SCANSOLO.KNOWLEDGE_CENTER.INDEX_ERROR_LABEL') }}:
              {{ source.indexError }}
            </p>
            <TechnicalDetails :items="sourceTechnicalItems(source)" />
          </div>
        </ScanSoloListState>
      </section>

      <section v-if="isAdministrator">
        <h2 class="text-sm font-medium text-n-slate-11 mb-2">
          {{ t('SCANSOLO.KNOWLEDGE_CENTER.RETRIEVAL_SIMULATOR_TITLE') }}
        </h2>
        <form class="flex gap-2 mb-4" @submit.prevent="runRetrievalTest">
          <input
            v-model="queryForm.query"
            type="text"
            data-testid="field-query"
            :placeholder="t('SCANSOLO.KNOWLEDGE_CENTER.FIELDS.QUERY')"
            class="flex-1 rounded-lg border border-n-weak px-3 py-2 text-sm"
          />
          <input
            v-model.number="queryForm.topK"
            type="number"
            min="1"
            :max="MAX_TOP_K"
            data-testid="field-top-k"
            class="w-20 rounded-lg border border-n-weak px-3 py-2 text-sm"
          />
          <button
            type="submit"
            data-testid="run-retrieval-button"
            :disabled="store.uiFlags.running"
            class="rounded-lg bg-n-slate-12 text-n-slate-1 px-4 py-2 text-sm disabled:opacity-50"
          >
            {{ t('SCANSOLO.KNOWLEDGE_CENTER.RUN_RETRIEVAL_TEST') }}
          </button>
        </form>

        <p
          v-if="store.retrievalFailureReason"
          data-testid="retrieval-failure-reason"
          class="text-sm text-n-ruby-9 mb-2"
        >
          {{ store.retrievalFailureReason }}
        </p>

        <div
          v-for="result in store.retrievalResults"
          :key="result.chunkId"
          data-testid="retrieval-result"
          class="rounded-lg border border-n-weak p-3 mb-2"
        >
          <p data-testid="retrieval-result-snippet" class="text-sm">
            {{ result.contentSnippet }}
          </p>
          <p class="text-xs text-n-slate-10">
            {{ t('SCANSOLO.KNOWLEDGE_CENTER.SOURCE_ID_LABEL') }}:
            {{ sourceTitle(result.sourceId) }}
            ·
            {{ t('SCANSOLO.KNOWLEDGE_CENTER.SIMILARITY_LABEL') }}:
            {{ result.similarityScore?.toFixed(2) }}
          </p>
          <TechnicalDetails :items="resultTechnicalItems(result)" />
        </div>
      </section>

      <ScanSoloConfirmDialog
        :show="!!sourcePendingDelete"
        :message="
          t('SCANSOLO.KNOWLEDGE_CENTER.DELETE_CONFIRM_MESSAGE', {
            title: sourcePendingDelete?.title,
          })
        "
        :confirm-label="t('SCANSOLO.KNOWLEDGE_CENTER.DELETE_CONFIRM')"
        @confirm="confirmRemoveSource"
        @cancel="sourcePendingDelete = null"
      />
    </div>
  </ScanSoloPageLayout>
</template>
