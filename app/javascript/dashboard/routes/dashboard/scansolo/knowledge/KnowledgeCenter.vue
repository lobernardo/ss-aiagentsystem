<script setup>
import ScanSoloPageLayout from 'dashboard/routes/dashboard/scansolo/components/ScanSoloPageLayout.vue';
import { onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useScansoloKnowledgeStore } from 'dashboard/store/scansolo/knowledgeSources';

const { t } = useI18n();
const store = useScansoloKnowledgeStore();

const SOURCE_TYPES = ['document', 'faq', 'company_info'];

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

onMounted(() => {
  store.fetchSources();
});

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

  await store.createSource(payload);

  Object.assign(form, emptyForm());
  if (fileInput.value) fileInput.value.value = '';
};

const toggleEnabled = source => {
  store.toggleEnabled(source.id, !source.enabled);
};

const reindex = source => {
  store.reindexSource(source.id);
};

const removeSource = source => {
  store.deleteSource(source.id);
};

const runRetrievalTest = () => {
  store.runRetrievalTest(queryForm.query, queryForm.topK);
};

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

      <section class="mb-8">
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
            class="rounded-lg bg-n-slate-12 text-n-slate-1 px-4 py-2 text-sm w-fit"
          >
            {{ t('SCANSOLO.KNOWLEDGE_CENTER.ADD_SOURCE') }}
          </button>
        </form>
      </section>

      <section class="mb-8">
        <h2 class="text-sm font-medium text-n-slate-11 mb-2">
          {{ t('SCANSOLO.KNOWLEDGE_CENTER.SOURCES_TITLE') }}
        </h2>
        <div
          v-for="source in store.sources"
          :key="source.id"
          data-testid="source-row"
          :data-source-id="source.id"
          class="flex items-center justify-between rounded-lg border border-n-weak p-3 mb-2"
        >
          <div>
            <p data-testid="source-title" class="text-sm font-medium">
              {{ source.title }}
            </p>
            <p class="text-xs text-n-slate-10">
              {{
                t(
                  `SCANSOLO.KNOWLEDGE_CENTER.SOURCE_TYPES.${source.sourceType?.toUpperCase()}`
                )
              }}
              ·
              <span data-testid="source-chunk-count">{{
                source.chunkCount
              }}</span>
            </p>
          </div>
          <div class="flex items-center gap-2">
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
          </div>
        </div>
      </section>

      <section>
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
            max="50"
            data-testid="field-top-k"
            class="w-20 rounded-lg border border-n-weak px-3 py-2 text-sm"
          />
          <button
            type="submit"
            data-testid="run-retrieval-button"
            class="rounded-lg bg-n-slate-12 text-n-slate-1 px-4 py-2 text-sm"
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
            {{ result.sourceId }}
            ·
            {{ t('SCANSOLO.KNOWLEDGE_CENTER.SIMILARITY_LABEL') }}:
            {{ result.similarityScore?.toFixed(2) }}
          </p>
        </div>
      </section>
    </div>
  </ScanSoloPageLayout>
</template>
