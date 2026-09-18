<script setup>
import { onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useScansoloExecutionsStore } from 'dashboard/store/scansolo/executions';

const { t } = useI18n();
const store = useScansoloExecutionsStore();

onMounted(() => {
  store.fetchExecutions();
});
</script>

<template>
  <div class="p-6 max-w-5xl mx-auto" data-testid="executions-screen">
    <h1 class="text-xl font-medium text-n-slate-12 mb-4">
      {{ t('SCANSOLO.EXECUTIONS.TITLE') }}
    </h1>

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
          <span data-testid="cadence-evidence-status">{{
            enrollment.status
          }}</span>
        </p>
        <div
          v-for="attempt in enrollment.attempts"
          :key="attempt.id"
          data-testid="cadence-evidence-attempt"
          class="text-xs text-n-slate-10 flex gap-3 mt-1"
        >
          <span
            >{{ t('SCANSOLO.EXECUTIONS.STEP_LABEL') }}: {{ attempt.step }}</span
          >
          <span data-testid="cadence-evidence-attempt-template">
            {{ t('SCANSOLO.EXECUTIONS.TEMPLATE_LABEL') }}:
            {{ attempt.templateReference }}
          </span>
          <span
            >{{ t('SCANSOLO.EXECUTIONS.RESULT_LABEL') }}:
            {{ attempt.result }}</span
          >
        </div>
      </div>
    </section>

    <section class="mb-8" data-testid="make-errors-section">
      <h2 class="text-sm font-medium text-n-slate-11 mb-2">
        {{ t('SCANSOLO.EXECUTIONS.MAKE_ERRORS_TITLE') }}
      </h2>

      <p
        v-if="!store.makeDeadLetters.length && !store.makeCallbackErrors.length"
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
          <p>
            {{ t('SCANSOLO.EXECUTIONS.ACTION_LABEL') }}: {{ request.action }}
          </p>
          <p>
            {{ t('SCANSOLO.EXECUTIONS.CORRELATION_ID_LABEL') }}:
            <span data-testid="make-dead-letter-correlation-id">{{
              request.correlationId
            }}</span>
          </p>
          <p>
            {{ t('SCANSOLO.EXECUTIONS.RETRY_COUNT_LABEL') }}:
            {{ request.retryCount }}
          </p>
          <p>
            {{ t('SCANSOLO.EXECUTIONS.STATUS_LABEL') }}: {{ request.status }}
          </p>
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
            {{ t('SCANSOLO.EXECUTIONS.ACTION_LABEL') }}: {{ callback.action }}
          </p>
          <p>
            {{ t('SCANSOLO.EXECUTIONS.CORRELATION_ID_LABEL') }}:
            <span data-testid="make-callback-error-correlation-id">{{
              callback.correlationId
            }}</span>
          </p>
          <p>
            {{ t('SCANSOLO.EXECUTIONS.REJECTION_REASON_LABEL') }}:
            <span data-testid="make-callback-error-reason">{{
              callback.rejectionReason
            }}</span>
          </p>
        </div>
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
          {{ t('SCANSOLO.EXECUTIONS.EVENT_TYPE_LABEL') }}: {{ event.eventType }}
        </p>
        <p>
          {{ t('SCANSOLO.EXECUTIONS.SUBJECT_LABEL') }}:
          {{ event.subjectType }} #{{ event.subjectId }}
        </p>
        <p>
          {{ t('SCANSOLO.EXECUTIONS.CORRELATION_ID_LABEL') }}:
          {{ event.correlationId }}
        </p>
      </div>
    </section>
  </div>
</template>
