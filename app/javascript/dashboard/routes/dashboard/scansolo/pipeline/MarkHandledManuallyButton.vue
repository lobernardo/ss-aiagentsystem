<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import ScanSoloConfirmDialog from 'dashboard/routes/dashboard/scansolo/components/ScanSoloConfirmDialog.vue';
import { useScansoloPipelineOpportunitiesStore } from 'dashboard/store/scansolo/pipelineOpportunities';
import { HANDLED_MANUALLY_ERROR_LABELS, enumLabel } from '../scansoloLabels';

const props = defineProps({
  opportunity: { type: Object, required: true },
});
const emit = defineEmits(['updated']);
// UI-08 / CT-03: single "proposta enviada manualmente" action. Nothing is
// sent now; the existing post-proposal cadence follows (RF-17, single mode).
const ELIGIBLE_COMMERCIAL_STATUS = 'aguardando_artur';
const ELIGIBLE_STAGES = ['qualificado', 'proposta_enviada'];

const { t } = useI18n();
const store = useScansoloPipelineOpportunitiesStore();

const showConfirm = ref(false);
const submitting = ref(false);

const isEligible = computed(
  () =>
    props.opportunity.commercialStatus === ELIGIBLE_COMMERCIAL_STATUS &&
    ELIGIBLE_STAGES.includes(props.opportunity.stage)
);

const confirm = async () => {
  showConfirm.value = false;
  submitting.value = true;
  try {
    const updated = await store.markHandledManually(props.opportunity.id);
    useAlert(t('SCANSOLO.HANDLED_MANUALLY.SUCCESS'));
    emit('updated', updated);
  } catch (error) {
    useAlert(
      enumLabel(
        t,
        HANDLED_MANUALLY_ERROR_LABELS,
        error?.response?.data?.error
      ) || t('SCANSOLO.COMMON.ACTION_ERROR')
    );
  } finally {
    submitting.value = false;
  }
};
</script>

<template>
  <!-- Inside a Kanban card: clicks here (and in the dialog) never open the lead. -->
  <div @click.stop>
    <div v-if="isEligible" class="mt-2">
      <Button
        type="button"
        size="sm"
        variant="outline"
        data-testid="mark-handled-manually-button"
        :label="t('SCANSOLO.HANDLED_MANUALLY.ACTION')"
        :is-loading="submitting"
        :disabled="submitting"
        @click="showConfirm = true"
      />
      <ScanSoloConfirmDialog
        :show="showConfirm"
        :message="t('SCANSOLO.HANDLED_MANUALLY.CONFIRM_MESSAGE')"
        :confirm-label="t('SCANSOLO.HANDLED_MANUALLY.ACTION')"
        @confirm="confirm"
        @cancel="showConfirm = false"
      />
    </div>
  </div>
</template>
