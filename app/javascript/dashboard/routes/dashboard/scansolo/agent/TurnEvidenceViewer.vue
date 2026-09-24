<script setup>
import ScanSoloPageLayout from 'dashboard/routes/dashboard/scansolo/components/ScanSoloPageLayout.vue';
import { onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useScansoloAiTurnsStore } from 'dashboard/store/scansolo/aiTurns';

const { t } = useI18n();
const store = useScansoloAiTurnsStore();

const searchForm = reactive({ correlationId: '' });
const selectedCorrelationId = ref(null);

onMounted(() => {
  store.fetchTurns();
});

const selectTurn = async correlationId => {
  selectedCorrelationId.value = correlationId;
  await store.fetchTurn(correlationId);
};

const searchByCorrelationId = () => {
  if (!searchForm.correlationId) return;
  selectTurn(searchForm.correlationId);
};

defineExpose({ selectTurn, searchByCorrelationId });
</script>

<template>
  <ScanSoloPageLayout>
    <div class="p-6 max-w-5xl mx-auto" data-testid="turn-evidence-viewer">
      <h1 class="text-xl font-medium text-n-slate-12 mb-4">
        {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.TITLE') }}
      </h1>

      <form class="flex gap-2 mb-6" @submit.prevent="searchByCorrelationId">
        <input
          v-model="searchForm.correlationId"
          type="text"
          data-testid="field-correlation-id"
          :placeholder="
            t('SCANSOLO.TURN_EVIDENCE_VIEWER.CORRELATION_ID_PLACEHOLDER')
          "
          class="flex-1 rounded-lg border border-n-weak px-3 py-2 text-sm"
        />
        <button
          type="submit"
          data-testid="search-turn-button"
          class="rounded-lg bg-n-slate-12 text-n-slate-1 px-4 py-2 text-sm"
        >
          {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.SEARCH') }}
        </button>
      </form>

      <div class="grid grid-cols-3 gap-6">
        <section class="col-span-1">
          <h2 class="text-sm font-medium text-n-slate-11 mb-2">
            {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.RECENT_TURNS_TITLE') }}
          </h2>
          <button
            v-for="turn in store.turns"
            :key="turn.correlationId"
            type="button"
            data-testid="turn-row"
            :data-correlation-id="turn.correlationId"
            class="w-full text-left rounded-lg border border-n-weak p-3 mb-2"
            :class="{
              'border-n-blue-9': selectedCorrelationId === turn.correlationId,
            }"
            @click="selectTurn(turn.correlationId)"
          >
            <p data-testid="turn-row-status" class="text-sm font-medium">
              {{ turn.invocationStatus }}
            </p>
            <p class="text-xs text-n-slate-10">{{ turn.correlationId }}</p>
          </button>
        </section>

        <section
          v-if="store.selectedTurn"
          data-testid="turn-detail"
          class="col-span-2 rounded-lg border border-n-weak p-4"
        >
          <h2 class="text-sm font-medium text-n-slate-11 mb-3">
            {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.DETAIL_TITLE') }}
          </h2>

          <dl class="grid grid-cols-2 gap-2 text-sm mb-4">
            <dt class="text-n-slate-10">
              {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.FIELDS.INVOCATION_STATUS') }}
            </dt>
            <dd data-testid="detail-invocation-status">
              {{ store.selectedTurn.invocationStatus }}
            </dd>

            <dt class="text-n-slate-10">
              {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.FIELDS.MODEL') }}
            </dt>
            <dd data-testid="detail-model">
              {{ store.selectedTurn.modelProvider }} /
              {{ store.selectedTurn.modelReference }}
            </dd>

            <dt class="text-n-slate-10">
              {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.FIELDS.TOKENS') }}
            </dt>
            <dd data-testid="detail-tokens">
              {{ store.selectedTurn.inputTokens }} /
              {{ store.selectedTurn.outputTokens }}
            </dd>

            <dt class="text-n-slate-10">
              {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.FIELDS.FAILURE_REASON') }}
            </dt>
            <dd data-testid="detail-failure-reason">
              {{ store.selectedTurn.failureReason }}
            </dd>
          </dl>

          <div class="mb-4">
            <h3 class="text-xs font-medium text-n-slate-11 mb-1">
              {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.GUARDRAIL_OUTCOME_TITLE') }}
            </h3>
            <pre
              data-testid="detail-guardrail-outcome"
              class="text-xs bg-n-solid-2 rounded-lg p-2 overflow-auto"
              >{{
                JSON.stringify(store.selectedTurn.guardrailOutcome, null, 2)
              }}</pre
            >
          </div>

          <div class="mb-4">
            <h3 class="text-xs font-medium text-n-slate-11 mb-1">
              {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.KNOWLEDGE_EVIDENCE_TITLE') }}
            </h3>
            <pre
              data-testid="detail-knowledge-evidence"
              class="text-xs bg-n-solid-2 rounded-lg p-2 overflow-auto"
              >{{
                JSON.stringify(store.selectedTurn.knowledgeEvidence, null, 2)
              }}</pre
            >
          </div>

          <div>
            <h3 class="text-xs font-medium text-n-slate-11 mb-1">
              {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.ACTION_EVIDENCE_TITLE') }}
            </h3>
            <pre
              data-testid="detail-action-evidence"
              class="text-xs bg-n-solid-2 rounded-lg p-2 overflow-auto"
              >{{
                JSON.stringify(store.selectedTurn.actionEvidence, null, 2)
              }}</pre
            >
          </div>
        </section>
      </div>
    </div>
  </ScanSoloPageLayout>
</template>
