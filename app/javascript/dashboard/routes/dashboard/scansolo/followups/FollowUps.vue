<script setup>
import ScanSoloPageLayout from 'dashboard/routes/dashboard/scansolo/components/ScanSoloPageLayout.vue';
import { onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useScansoloCadenceEnrollmentsStore } from 'dashboard/store/scansolo/cadenceEnrollments';

const { t } = useI18n();
const store = useScansoloCadenceEnrollmentsStore();

onMounted(() => {
  store.fetchEnrollments();
});

const pause = enrollment => store.pauseEnrollment(enrollment.id);
const resume = enrollment => store.resumeEnrollment(enrollment.id);
const cancel = enrollment => store.cancelEnrollment(enrollment.id);

defineExpose({ pause, resume, cancel });
</script>

<template>
  <ScanSoloPageLayout>
    <div class="p-6 max-w-4xl mx-auto" data-testid="follow-ups-screen">
      <h1 class="text-xl font-medium text-n-slate-12 mb-4">
        {{ t('SCANSOLO.FOLLOW_UPS.TITLE') }}
      </h1>

      <p
        v-if="!store.enrollments.length"
        data-testid="follow-ups-empty-state"
        class="text-sm text-n-slate-10"
      >
        {{ t('SCANSOLO.FOLLOW_UPS.EMPTY_STATE') }}
      </p>

      <div
        v-for="enrollment in store.enrollments"
        :key="enrollment.id"
        data-testid="enrollment-row"
        :data-enrollment-id="enrollment.id"
        class="flex items-center justify-between rounded-lg border border-n-weak p-3 mb-2"
      >
        <div>
          <p data-testid="enrollment-contact-name" class="text-sm font-medium">
            {{ enrollment.contactName }}
          </p>
          <p class="text-xs text-n-slate-10">
            {{ t('SCANSOLO.FOLLOW_UPS.CURRENT_STEP_LABEL') }}:
            <span data-testid="enrollment-current-step">{{
              enrollment.currentStep
            }}</span>
            ·
            {{ t('SCANSOLO.FOLLOW_UPS.NEXT_ATTEMPT_LABEL') }}:
            <span data-testid="enrollment-next-attempt">{{
              enrollment.nextAttemptAt || t('SCANSOLO.FOLLOW_UPS.NOT_SCHEDULED')
            }}</span>
          </p>
        </div>
        <div class="flex items-center gap-2">
          <span
            data-testid="enrollment-status"
            class="text-xs font-medium px-2 py-1 rounded-full bg-n-slate-3 text-n-slate-11"
          >
            {{
              t(
                `SCANSOLO.FOLLOW_UPS.STATUSES.${enrollment.status?.toUpperCase()}`
              )
            }}
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
    </div>
  </ScanSoloPageLayout>
</template>
