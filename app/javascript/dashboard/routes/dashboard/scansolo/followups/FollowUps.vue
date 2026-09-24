<script setup>
import ScanSoloPageLayout from 'dashboard/routes/dashboard/scansolo/components/ScanSoloPageLayout.vue';
import ScanSoloListState from 'dashboard/routes/dashboard/scansolo/components/ScanSoloListState.vue';
import ScanSoloConfirmDialog from 'dashboard/routes/dashboard/scansolo/components/ScanSoloConfirmDialog.vue';
import ScanSoloTime from 'dashboard/routes/dashboard/scansolo/components/ScanSoloTime.vue';
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useScansoloCadenceEnrollmentsStore } from 'dashboard/store/scansolo/cadenceEnrollments';
import TemplatesPanel from './TemplatesPanel.vue';
import { ENROLLMENT_STATUS_LABELS, enumLabel } from '../scansoloLabels';
import { serverErrorMessage } from '../scansoloErrors';

const { t } = useI18n();
const store = useScansoloCadenceEnrollmentsStore();

const loadError = ref(false);
const enrollmentPendingCancel = ref(null);

const loadEnrollments = async () => {
  loadError.value = false;
  try {
    await store.fetchEnrollments();
  } catch (error) {
    loadError.value = true;
  }
};

onMounted(loadEnrollments);

const runMutation = async (mutation, successKey) => {
  try {
    await mutation();
    useAlert(t(successKey));
  } catch (error) {
    useAlert(serverErrorMessage(error, t('SCANSOLO.COMMON.ACTION_ERROR')));
  }
};

const pause = enrollment =>
  runMutation(
    () => store.pauseEnrollment(enrollment.id),
    'SCANSOLO.FOLLOW_UPS.PAUSE_SUCCESS'
  );

const resume = enrollment =>
  runMutation(
    () => store.resumeEnrollment(enrollment.id),
    'SCANSOLO.FOLLOW_UPS.RESUME_SUCCESS'
  );

// UI-09: cancelling a follow-up always goes through the confirmation first.
const cancel = enrollment => {
  enrollmentPendingCancel.value = enrollment;
};

const confirmCancel = async () => {
  const enrollment = enrollmentPendingCancel.value;
  enrollmentPendingCancel.value = null;
  await runMutation(
    () => store.cancelEnrollment(enrollment.id),
    'SCANSOLO.FOLLOW_UPS.CANCEL_SUCCESS'
  );
};

defineExpose({ pause, resume, cancel });
</script>

<template>
  <ScanSoloPageLayout>
    <div class="p-6 max-w-4xl mx-auto" data-testid="follow-ups-screen">
      <h1 class="text-xl font-medium text-n-slate-12 mb-4">
        {{ t('SCANSOLO.FOLLOW_UPS.TITLE') }}
      </h1>

      <ScanSoloListState
        :loading="store.uiFlags.fetchingList"
        :error="loadError"
        :empty="!store.enrollments.length"
        :empty-message="t('SCANSOLO.FOLLOW_UPS.EMPTY_STATE')"
        @retry="loadEnrollments"
      >
        <div
          v-for="enrollment in store.enrollments"
          :key="enrollment.id"
          data-testid="enrollment-row"
          :data-enrollment-id="enrollment.id"
          class="flex items-center justify-between rounded-lg border border-n-weak p-3 mb-2"
        >
          <div>
            <p
              data-testid="enrollment-contact-name"
              class="text-sm font-medium"
            >
              {{ enrollment.contactName }}
            </p>
            <p class="text-xs text-n-slate-10">
              {{ t('SCANSOLO.FOLLOW_UPS.CURRENT_STEP_LABEL') }}:
              <span data-testid="enrollment-current-step">{{
                enrollment.currentStep
              }}</span>
              ·
              {{ t('SCANSOLO.FOLLOW_UPS.NEXT_ATTEMPT_LABEL') }}:
              <ScanSoloTime
                data-testid="enrollment-next-attempt"
                :value="enrollment.nextAttemptAt"
                :fallback="t('SCANSOLO.FOLLOW_UPS.NOT_SCHEDULED')"
              />
            </p>
          </div>
          <div class="flex items-center gap-2">
            <span
              data-testid="enrollment-status"
              class="text-xs font-medium px-2 py-1 rounded-full bg-n-slate-3 text-n-slate-11"
            >
              {{ enumLabel(t, ENROLLMENT_STATUS_LABELS, enrollment.status) }}
            </span>
            <button
              v-if="enrollment.status === 'active'"
              type="button"
              data-testid="pause-button"
              class="rounded-lg border border-n-weak px-3 py-1.5 text-sm"
              @click="pause(enrollment)"
            >
              {{ t('SCANSOLO.FOLLOW_UPS.PAUSE') }}
            </button>
            <button
              v-if="enrollment.status === 'paused'"
              type="button"
              data-testid="resume-button"
              class="rounded-lg border border-n-weak px-3 py-1.5 text-sm"
              @click="resume(enrollment)"
            >
              {{ t('SCANSOLO.FOLLOW_UPS.RESUME') }}
            </button>
            <button
              v-if="['active', 'paused'].includes(enrollment.status)"
              type="button"
              data-testid="cancel-button"
              class="rounded-lg border border-n-ruby-9 text-n-ruby-9 px-3 py-1.5 text-sm"
              @click="cancel(enrollment)"
            >
              {{ t('SCANSOLO.FOLLOW_UPS.CANCEL') }}
            </button>
          </div>
        </div>
      </ScanSoloListState>

      <TemplatesPanel />

      <ScanSoloConfirmDialog
        :show="!!enrollmentPendingCancel"
        :message="
          t('SCANSOLO.FOLLOW_UPS.CANCEL_CONFIRM_MESSAGE', {
            name: enrollmentPendingCancel?.contactName,
          })
        "
        :confirm-label="t('SCANSOLO.FOLLOW_UPS.CANCEL_CONFIRM')"
        :cancel-label="t('SCANSOLO.FOLLOW_UPS.KEEP')"
        @confirm="confirmCancel"
        @cancel="enrollmentPendingCancel = null"
      />
    </div>
  </ScanSoloPageLayout>
</template>
