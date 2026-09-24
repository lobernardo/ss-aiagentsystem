<script setup>
import ScanSoloPageLayout from 'dashboard/routes/dashboard/scansolo/components/ScanSoloPageLayout.vue';
import ScanSoloListState from 'dashboard/routes/dashboard/scansolo/components/ScanSoloListState.vue';
import ScanSoloConfirmDialog from 'dashboard/routes/dashboard/scansolo/components/ScanSoloConfirmDialog.vue';
import ScanSoloTime from 'dashboard/routes/dashboard/scansolo/components/ScanSoloTime.vue';
import TechnicalDetails from 'dashboard/routes/dashboard/scansolo/components/TechnicalDetails.vue';
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useScansoloExecutionsStore } from 'dashboard/store/scansolo/executions';
import { useScanSoloRole } from '../composables/useScanSoloRole';
import { serverErrorMessage } from '../scansoloErrors';
import {
  ATTEMPT_RESULT_LABELS,
  AVAILABILITY_LABELS,
  CALLBACK_REJECTION_LABELS,
  ENROLLMENT_STATUS_LABELS,
  ERROR_KIND_LABELS,
  HANDOFF_EVENT_LABELS,
  HANDOFF_TRIGGER_LABELS,
  MAKE_ACTION_LABELS,
  REASON_LABELS,
  STAGE_LABELS,
  enumLabel,
} from '../scansoloLabels';

const { t } = useI18n();
const store = useScansoloExecutionsStore();
const { isAdministrator } = useScanSoloRole();

const loadError = ref(false);
const deadLetterPendingReprocess = ref(null);

const loadExecutions = async () => {
  loadError.value = false;
  try {
    await store.fetchExecutions();
  } catch (error) {
    loadError.value = true;
  }
};

onMounted(loadExecutions);

// UI-09: reprocessing a dead letter always asks first (administrators only).
const requestReprocess = deadLetter => {
  deadLetterPendingReprocess.value = deadLetter;
};

const confirmReprocess = async () => {
  const deadLetter = deadLetterPendingReprocess.value;
  deadLetterPendingReprocess.value = null;
  try {
    await store.reprocessDeadLetter(deadLetter);
    useAlert(t('SCANSOLO.EXECUTIONS.REPROCESS_SUCCESS'));
  } catch (error) {
    useAlert(serverErrorMessage(error, t('SCANSOLO.COMMON.ACTION_ERROR')));
  }
};

const templateStepLabel = row =>
  row.step === null
    ? t('SCANSOLO.FOLLOW_UPS.TEMPLATES.PROPOSAL_SEND')
    : t('SCANSOLO.FOLLOW_UPS.TEMPLATES.STEP_LABEL', { step: row.step });

// Label keys are the static SCANSOLO.TECHNICAL_DETAILS.* strings in the template.
const technical = entries =>
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  entries.map(([labelKey, value]) => ({ label: t(labelKey), value }));

defineExpose({ requestReprocess, confirmReprocess });
</script>

<template>
  <ScanSoloPageLayout>
    <div class="p-6 max-w-5xl mx-auto" data-testid="executions-screen">
      <h1 class="text-xl font-medium text-n-slate-12 mb-4">
        {{ t('SCANSOLO.EXECUTIONS.TITLE') }}
      </h1>

      <ScanSoloListState
        :loading="store.uiFlags.fetchingList"
        :error="loadError"
        @retry="loadExecutions"
      >
        <section class="mb-8">
          <h2 class="text-sm font-medium text-n-slate-11 mb-2">
            {{ t('SCANSOLO.EXECUTIONS.CADENCE_EVIDENCE_TITLE') }}
          </h2>
          <p
            v-if="!store.cadenceEvidence.length"
            data-testid="cadence-evidence-empty-state"
            class="text-sm text-n-slate-10"
          >
            {{ t('SCANSOLO.EXECUTIONS.CADENCE_EVIDENCE_EMPTY_STATE') }}
          </p>
          <div
            v-for="enrollment in store.cadenceEvidence"
            :key="enrollment.id"
            data-testid="cadence-evidence-row"
            :data-enrollment-id="enrollment.id"
            class="rounded-lg border border-n-weak p-3 mb-2"
          >
            <p class="text-sm font-medium">
              {{ enrollment.contactName }} ·
              {{ enumLabel(t, STAGE_LABELS, enrollment.cadenceStage) }} ·
              <span data-testid="cadence-evidence-status">{{
                enumLabel(t, ENROLLMENT_STATUS_LABELS, enrollment.status)
              }}</span>
            </p>
            <div
              v-for="attempt in enrollment.attempts"
              :key="attempt.id"
              data-testid="cadence-evidence-attempt"
              :data-attempt-id="attempt.id"
              class="mt-2 border-t border-n-weak pt-2 text-xs text-n-slate-10"
            >
              <p class="flex flex-wrap gap-x-3">
                <span>
                  {{ t('SCANSOLO.EXECUTIONS.STEP_LABEL') }}: {{ attempt.step }}
                </span>
                <span data-testid="cadence-evidence-attempt-template">
                  {{ t('SCANSOLO.EXECUTIONS.TEMPLATE_LABEL') }}:
                  {{ attempt.templateReference }}
                </span>
                <span>
                  {{ t('SCANSOLO.EXECUTIONS.SCHEDULED_AT_LABEL') }}:
                  <ScanSoloTime :value="attempt.scheduledAt" />
                </span>
                <span data-testid="cadence-evidence-attempt-result">
                  {{ t('SCANSOLO.EXECUTIONS.RESULT_LABEL') }}:
                  {{ enumLabel(t, ATTEMPT_RESULT_LABELS, attempt.result) }}
                </span>
              </p>
              <p
                v-if="attempt.lastBlockReason"
                data-testid="cadence-evidence-attempt-block-reason"
              >
                {{ t('SCANSOLO.EXECUTIONS.BLOCK_REASON_LABEL') }}:
                {{ enumLabel(t, REASON_LABELS, attempt.lastBlockReason) }}
                · {{ t('SCANSOLO.EXECUTIONS.LAST_CHECKED_LABEL') }}:
                <ScanSoloTime :value="attempt.lastCheckedAt" />
              </p>
              <p
                v-if="attempt.messageId"
                data-testid="cadence-evidence-attempt-delivery"
              >
                {{ t('SCANSOLO.EXECUTIONS.DELIVERY_EVIDENCE_LABEL') }}:
                {{ t('SCANSOLO.EXECUTIONS.MESSAGE_CREATED') }}
                <template v-if="attempt.sentAt">
                  · <ScanSoloTime :value="attempt.sentAt" />
                </template>
              </p>
              <p
                v-if="attempt.externalError"
                data-testid="cadence-evidence-attempt-external-error"
                class="text-n-ruby-11"
              >
                {{ t('SCANSOLO.EXECUTIONS.EXTERNAL_ERROR_LABEL') }}:
                {{ attempt.externalError }}
              </p>
              <TechnicalDetails
                :items="
                  technical([
                    ['SCANSOLO.TECHNICAL_DETAILS.ID', attempt.id],
                    [
                      'SCANSOLO.TECHNICAL_DETAILS.MESSAGE_ID',
                      attempt.messageId,
                    ],
                  ])
                "
              />
            </div>
          </div>
        </section>

        <section class="mb-8" data-testid="template-availability-section">
          <h2 class="text-sm font-medium text-n-slate-11 mb-2">
            {{ t('SCANSOLO.EXECUTIONS.TEMPLATE_AVAILABILITY_TITLE') }}
          </h2>
          <p
            v-if="!store.templateAvailability.length"
            class="text-sm text-n-slate-10"
          >
            {{ t('SCANSOLO.EXECUTIONS.TEMPLATE_AVAILABILITY_EMPTY_STATE') }}
          </p>
          <p
            v-for="row in store.templateAvailability"
            :key="`${row.stage}:${row.step}`"
            data-testid="template-availability-row"
            class="text-xs text-n-slate-11 mb-1"
          >
            {{ enumLabel(t, STAGE_LABELS, row.stage) }} ·
            {{ templateStepLabel(row) }} · {{ row.templateName }} ·
            <span data-testid="template-availability-state">{{
              enumLabel(t, AVAILABILITY_LABELS, row.availability)
            }}</span>
            <template v-if="row.blockReason">
              · {{ enumLabel(t, REASON_LABELS, row.blockReason) }}
            </template>
          </p>
        </section>

        <section class="mb-8" data-testid="make-errors-section">
          <h2 class="text-sm font-medium text-n-slate-11 mb-2">
            {{ t('SCANSOLO.EXECUTIONS.MAKE_ERRORS_TITLE') }}
          </h2>
          <p
            v-if="
              !store.makeDeadLetters.length && !store.makeCallbackErrors.length
            "
            data-testid="make-errors-empty-state"
            class="text-sm text-n-slate-10"
          >
            {{ t('SCANSOLO.EXECUTIONS.MAKE_ERRORS_EMPTY_STATE') }}
          </p>

          <div v-if="store.makeDeadLetters.length" class="mb-3">
            <h3 class="text-xs font-medium text-n-slate-11 mb-1">
              {{ t('SCANSOLO.EXECUTIONS.DEAD_LETTERS_TITLE') }}
            </h3>
            <div
              v-for="request in store.makeDeadLetters"
              :key="request.id"
              data-testid="make-dead-letter-row"
              :data-request-id="request.id"
              class="rounded-lg border border-n-ruby-6 bg-n-ruby-2 p-3 mb-2 text-xs"
            >
              <div class="flex items-center justify-between gap-2">
                <p>
                  {{ enumLabel(t, MAKE_ACTION_LABELS, request.action) }} ·
                  {{ t('SCANSOLO.EXECUTIONS.RETRY_COUNT_LABEL') }}:
                  {{ request.retryCount }} ·
                  <ScanSoloTime :value="request.createdAt" />
                </p>
                <button
                  v-if="isAdministrator && request.proposalVersionId"
                  type="button"
                  data-testid="reprocess-button"
                  class="rounded-lg border border-n-ruby-9 px-3 py-1.5 text-sm text-n-ruby-11"
                  @click="requestReprocess(request)"
                >
                  {{ t('SCANSOLO.EXECUTIONS.REPROCESS') }}
                </button>
              </div>
              <TechnicalDetails
                :items="
                  technical([
                    [
                      'SCANSOLO.TECHNICAL_DETAILS.CORRELATION_ID',
                      request.correlationId,
                    ],
                    [
                      'SCANSOLO.TECHNICAL_DETAILS.IDEMPOTENCY_KEY',
                      request.idempotencyKey,
                    ],
                    [
                      'SCANSOLO.TECHNICAL_DETAILS.PROPOSAL_VERSION_ID',
                      request.proposalVersionId,
                    ],
                  ])
                "
              />
            </div>
          </div>

          <div v-if="store.makeCallbackErrors.length">
            <h3 class="text-xs font-medium text-n-slate-11 mb-1">
              {{ t('SCANSOLO.EXECUTIONS.CALLBACK_ERRORS_TITLE') }}
            </h3>
            <div
              v-for="callback in store.makeCallbackErrors"
              :key="callback.id"
              data-testid="make-callback-error-row"
              :data-callback-id="callback.id"
              class="rounded-lg border border-n-ruby-6 bg-n-ruby-2 p-3 mb-2 text-xs"
            >
              <p>
                {{ enumLabel(t, MAKE_ACTION_LABELS, callback.action) }} ·
                {{ t('SCANSOLO.EXECUTIONS.REJECTION_REASON_LABEL') }}:
                <span data-testid="make-callback-error-reason">{{
                  enumLabel(
                    t,
                    CALLBACK_REJECTION_LABELS,
                    callback.rejectionReason
                  )
                }}</span>
                · <ScanSoloTime :value="callback.createdAt" />
              </p>
              <TechnicalDetails
                :items="
                  technical([
                    [
                      'SCANSOLO.TECHNICAL_DETAILS.CORRELATION_ID',
                      callback.correlationId,
                    ],
                  ])
                "
              />
            </div>
          </div>
        </section>

        <section class="mb-8" data-testid="handoff-events-section">
          <h2 class="text-sm font-medium text-n-slate-11 mb-2">
            {{ t('SCANSOLO.EXECUTIONS.HANDOFF_EVENTS_TITLE') }}
          </h2>
          <p
            v-if="!store.handoffEvents.length"
            data-testid="handoff-events-empty-state"
            class="text-sm text-n-slate-10"
          >
            {{ t('SCANSOLO.EXECUTIONS.HANDOFF_EVENTS_EMPTY_STATE') }}
          </p>
          <div
            v-for="event in store.handoffEvents"
            :key="event.id"
            data-testid="handoff-event-row"
            :data-event-id="event.id"
            class="rounded-lg border border-n-weak p-3 mb-2 text-xs"
          >
            <span data-testid="handoff-event-type">{{
              enumLabel(t, HANDOFF_EVENT_LABELS, event.eventType)
            }}</span>
            · {{ t('SCANSOLO.EXECUTIONS.TRIGGER_LABEL') }}:
            <span data-testid="handoff-event-trigger">{{
              enumLabel(t, HANDOFF_TRIGGER_LABELS, event.trigger)
            }}</span>
            · <ScanSoloTime :value="event.createdAt" />
            <TechnicalDetails
              :items="
                technical([
                  [
                    'SCANSOLO.TECHNICAL_DETAILS.CONVERSATION_ID',
                    event.conversationId,
                  ],
                  [
                    'SCANSOLO.TECHNICAL_DETAILS.ACTOR',
                    event.actorType && `${event.actorType} #${event.actorId}`,
                  ],
                  [
                    'SCANSOLO.TECHNICAL_DETAILS.CORRELATION_ID',
                    event.correlationId,
                  ],
                ])
              "
            />
          </div>
        </section>

        <section class="mb-8" data-testid="recent-errors-section">
          <h2 class="text-sm font-medium text-n-slate-11 mb-2">
            {{ t('SCANSOLO.EXECUTIONS.RECENT_ERRORS_TITLE') }}
          </h2>
          <p
            v-if="!store.recentErrors.length"
            data-testid="recent-errors-empty-state"
            class="text-sm text-n-slate-10"
          >
            {{ t('SCANSOLO.EXECUTIONS.RECENT_ERRORS_EMPTY_STATE') }}
          </p>
          <div
            v-for="error in store.recentErrors"
            :key="`${error.kind}:${error.id}`"
            data-testid="recent-error-row"
            class="rounded-lg border border-n-weak p-3 mb-2 text-xs"
          >
            <p>
              <span data-testid="recent-error-kind">{{
                enumLabel(t, ERROR_KIND_LABELS, error.kind)
              }}</span>
              · {{ t('SCANSOLO.EXECUTIONS.REASON_LABEL') }}:
              <span data-testid="recent-error-reason">{{
                enumLabel(t, REASON_LABELS, error.reason)
              }}</span>
              · <ScanSoloTime :value="error.occurredAt" />
            </p>
            <TechnicalDetails
              :items="
                technical([
                  ['SCANSOLO.TECHNICAL_DETAILS.ID', error.id],
                  [
                    'SCANSOLO.TECHNICAL_DETAILS.CORRELATION_ID',
                    error.correlationId,
                  ],
                ])
              "
            />
          </div>
        </section>

        <section>
          <h2 class="text-sm font-medium text-n-slate-11 mb-2">
            {{ t('SCANSOLO.EXECUTIONS.AUDIT_EVENTS_TITLE') }}
          </h2>
          <p
            v-if="!store.auditEvents.length"
            data-testid="audit-events-empty-state"
            class="text-sm text-n-slate-10"
          >
            {{ t('SCANSOLO.EXECUTIONS.AUDIT_EVENTS_EMPTY_STATE') }}
          </p>
          <div
            v-for="event in store.auditEvents"
            :key="event.id"
            data-testid="audit-event-row"
            :data-event-id="event.id"
            class="rounded-lg border border-n-weak p-3 mb-2 text-xs"
          >
            <p data-testid="audit-event-type">
              {{ t('SCANSOLO.EXECUTIONS.EVENT_TYPE_LABEL') }}:
              {{ event.eventType }} · <ScanSoloTime :value="event.createdAt" />
            </p>
            <TechnicalDetails
              :items="
                technical([
                  [
                    'SCANSOLO.TECHNICAL_DETAILS.SUBJECT',
                    `${event.subjectType} #${event.subjectId}`,
                  ],
                  [
                    'SCANSOLO.TECHNICAL_DETAILS.CORRELATION_ID',
                    event.correlationId,
                  ],
                  ['SCANSOLO.TECHNICAL_DETAILS.RAW_PAYLOAD', event.payload],
                ])
              "
            />
          </div>
        </section>
      </ScanSoloListState>

      <ScanSoloConfirmDialog
        :show="!!deadLetterPendingReprocess"
        :message="t('SCANSOLO.EXECUTIONS.REPROCESS_CONFIRM_MESSAGE')"
        :confirm-label="t('SCANSOLO.EXECUTIONS.REPROCESS_CONFIRM')"
        @confirm="confirmReprocess"
        @cancel="deadLetterPendingReprocess = null"
      />
    </div>
  </ScanSoloPageLayout>
</template>
