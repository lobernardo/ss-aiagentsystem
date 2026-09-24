<script setup>
import ScanSoloPageLayout from 'dashboard/routes/dashboard/scansolo/components/ScanSoloPageLayout.vue';
import ScanSoloListState from 'dashboard/routes/dashboard/scansolo/components/ScanSoloListState.vue';
import ScanSoloTime from 'dashboard/routes/dashboard/scansolo/components/ScanSoloTime.vue';
import TechnicalDetails from 'dashboard/routes/dashboard/scansolo/components/TechnicalDetails.vue';
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useScansoloAiTurnsStore } from 'dashboard/store/scansolo/aiTurns';
import { useScanSoloRole } from '../composables/useScanSoloRole';
import { serverErrorMessage } from '../scansoloErrors';
import {
  AI_ACTION_LABELS,
  DELIVERY_STATUS_LABELS,
  REASON_LABELS,
  TURN_STATUS_LABELS,
  enumLabel,
} from '../scansoloLabels';

const { t } = useI18n();
const store = useScansoloAiTurnsStore();
const { isAdministrator } = useScanSoloRole();

const searchForm = reactive({ correlationId: '' });
const selectedTurnId = ref(null);
const loadError = ref(false);

const loadTurns = async () => {
  loadError.value = false;
  try {
    await store.fetchTurns();
  } catch (error) {
    loadError.value = true;
  }
};

onMounted(loadTurns);

const selectTurn = async turn => {
  selectedTurnId.value = turn.id;
  try {
    await store.fetchTurn(turn.correlationId);
  } catch (error) {
    useAlert(serverErrorMessage(error, t('SCANSOLO.COMMON.ACTION_ERROR')));
  }
};

// Administrators only: the correlation id is a technical identifier (D-18).
const searchByCorrelationId = async () => {
  if (!searchForm.correlationId) return;
  try {
    const turn = await store.fetchTurn(searchForm.correlationId);
    selectedTurnId.value = turn?.id;
  } catch (error) {
    useAlert(serverErrorMessage(error, t('SCANSOLO.COMMON.ACTION_ERROR')));
  }
};

const selectedTurn = computed(() => store.selectedTurn);

const knowledgeEvidence = computed(() =>
  Array.isArray(selectedTurn.value?.knowledgeEvidence)
    ? selectedTurn.value.knowledgeEvidence
    : []
);

const actionEvidence = computed(() =>
  Array.isArray(selectedTurn.value?.actionEvidence)
    ? selectedTurn.value.actionEvidence
    : []
);

const formatScore = score =>
  typeof score === 'number' ? score.toFixed(2) : '';

const technicalItems = computed(() => {
  const turn = selectedTurn.value;
  return [
    {
      label: t('SCANSOLO.TECHNICAL_DETAILS.CORRELATION_ID'),
      value: turn.correlationId,
    },
    {
      label: t('SCANSOLO.TECHNICAL_DETAILS.CONVERSATION_ID'),
      value: turn.conversationId,
    },
    {
      label: t('SCANSOLO.TECHNICAL_DETAILS.MESSAGE_ID'),
      value: turn.messageId,
    },
    { label: t('SCANSOLO.TECHNICAL_DETAILS.TIMESTAMP'), value: turn.createdAt },
    {
      label: t('SCANSOLO.TECHNICAL_DETAILS.RAW_GUARDRAIL'),
      value: turn.guardrailOutcome,
    },
    {
      label: t('SCANSOLO.TECHNICAL_DETAILS.RAW_ACTIONS'),
      value: turn.actionEvidence,
    },
    {
      label: t('SCANSOLO.TECHNICAL_DETAILS.RAW_CONTEXT'),
      value: turn.contextSnapshot,
    },
  ];
});

defineExpose({ selectTurn, searchByCorrelationId });
</script>

<template>
  <ScanSoloPageLayout>
    <div class="p-6 max-w-5xl mx-auto" data-testid="turn-evidence-viewer">
      <h1 class="text-xl font-medium text-n-slate-12 mb-4">
        {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.TITLE') }}
      </h1>

      <form
        v-if="isAdministrator"
        class="flex gap-2 mb-6"
        @submit.prevent="searchByCorrelationId"
      >
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

      <div class="grid grid-cols-1 gap-6 md:grid-cols-3">
        <section class="md:col-span-1">
          <h2 class="text-sm font-medium text-n-slate-11 mb-2">
            {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.RECENT_TURNS_TITLE') }}
          </h2>
          <ScanSoloListState
            :loading="store.uiFlags.fetchingTurns"
            :error="loadError"
            :empty="!store.turns.length"
            :empty-message="t('SCANSOLO.TURN_EVIDENCE_VIEWER.EMPTY_STATE')"
            @retry="loadTurns"
          >
            <button
              v-for="turn in store.turns"
              :key="turn.id"
              type="button"
              data-testid="turn-row"
              :data-turn-id="turn.id"
              class="w-full text-start rounded-lg border border-n-weak p-3 mb-2"
              :class="{ 'border-n-blue-9': selectedTurnId === turn.id }"
              @click="selectTurn(turn)"
            >
              <p data-testid="turn-row-status" class="text-sm font-medium">
                {{ enumLabel(t, TURN_STATUS_LABELS, turn.invocationStatus) }}
              </p>
              <p class="text-xs text-n-slate-10">
                <ScanSoloTime :value="turn.createdAt" />
              </p>
            </button>
          </ScanSoloListState>
        </section>

        <section
          v-if="selectedTurn"
          data-testid="turn-detail"
          class="md:col-span-2 rounded-lg border border-n-weak p-4"
        >
          <h2 class="text-sm font-medium text-n-slate-11 mb-3">
            {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.DETAIL_TITLE') }}
          </h2>

          <dl class="grid grid-cols-2 gap-2 text-sm mb-4">
            <dt class="text-n-slate-10">
              {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.FIELDS.INVOCATION_STATUS') }}
            </dt>
            <dd data-testid="detail-invocation-status">
              {{
                enumLabel(t, TURN_STATUS_LABELS, selectedTurn.invocationStatus)
              }}
            </dd>

            <dt class="text-n-slate-10">
              {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.FIELDS.MODEL') }}
            </dt>
            <dd data-testid="detail-model">
              {{ selectedTurn.modelProvider }} /
              {{ selectedTurn.modelReference }}
            </dd>

            <dt class="text-n-slate-10">
              {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.FIELDS.TOKENS') }}
            </dt>
            <dd data-testid="detail-tokens">
              {{ selectedTurn.inputTokens }} / {{ selectedTurn.outputTokens }}
            </dd>

            <dt class="text-n-slate-10">
              {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.FIELDS.LATENCY') }}
            </dt>
            <dd data-testid="detail-latency">
              {{
                selectedTurn.latencyMs === null ||
                selectedTurn.latencyMs === undefined
                  ? t('SCANSOLO.COMMON.NOT_AVAILABLE')
                  : t('SCANSOLO.TURN_EVIDENCE_VIEWER.LATENCY_VALUE', {
                      ms: selectedTurn.latencyMs,
                    })
              }}
            </dd>

            <dt class="text-n-slate-10">
              {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.FIELDS.DELIVERY_STATUS') }}
            </dt>
            <dd data-testid="detail-delivery-status">
              {{
                enumLabel(
                  t,
                  DELIVERY_STATUS_LABELS,
                  selectedTurn.responseDeliveryStatus
                ) || t('SCANSOLO.TURN_EVIDENCE_VIEWER.NOT_DELIVERED')
              }}
            </dd>

            <dt class="text-n-slate-10">
              {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.FIELDS.CREATED_AT') }}
            </dt>
            <dd>
              <ScanSoloTime :value="selectedTurn.createdAt" />
            </dd>

            <dt class="text-n-slate-10">
              {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.FIELDS.FAILURE_REASON') }}
            </dt>
            <dd data-testid="detail-failure-reason">
              {{ enumLabel(t, REASON_LABELS, selectedTurn.failureReason) }}
            </dd>
          </dl>

          <div class="mb-4">
            <h3 class="text-xs font-medium text-n-slate-11 mb-1">
              {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.KNOWLEDGE_EVIDENCE_TITLE') }}
            </h3>
            <ul
              v-if="knowledgeEvidence.length"
              data-testid="detail-knowledge-evidence"
              class="text-sm"
            >
              <li
                v-for="evidence in knowledgeEvidence"
                :key="evidence.chunkId"
                data-testid="knowledge-evidence-item"
              >
                {{
                  evidence.sourceTitle ||
                  t('SCANSOLO.TURN_EVIDENCE_VIEWER.UNTITLED_SOURCE')
                }}
                · {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.SCORE_LABEL') }}:
                {{ formatScore(evidence.similarityScore) }}
              </li>
            </ul>
            <p
              v-else
              data-testid="detail-knowledge-evidence-empty"
              class="text-sm text-n-slate-10"
            >
              {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.NO_KNOWLEDGE_EVIDENCE') }}
            </p>
          </div>

          <div class="mb-4">
            <h3 class="text-xs font-medium text-n-slate-11 mb-1">
              {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.ACTION_EVIDENCE_TITLE') }}
            </h3>
            <ul
              v-if="actionEvidence.length"
              data-testid="detail-action-evidence"
              class="text-sm"
            >
              <li v-for="action in actionEvidence" :key="action.index">
                {{ enumLabel(t, AI_ACTION_LABELS, action.actionId) }}
              </li>
            </ul>
            <p v-else class="text-sm text-n-slate-10">
              {{ t('SCANSOLO.TURN_EVIDENCE_VIEWER.NO_ACTION_EVIDENCE') }}
            </p>
          </div>

          <TechnicalDetails :items="technicalItems" />
        </section>
      </div>
    </div>
  </ScanSoloPageLayout>
</template>
