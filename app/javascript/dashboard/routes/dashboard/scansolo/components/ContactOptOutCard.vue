<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ScanSoloContactsAPI from 'dashboard/api/scansoloContacts';
import ScanSoloListState from './ScanSoloListState.vue';
import ScanSoloConfirmDialog from './ScanSoloConfirmDialog.vue';
import { useScanSoloRole } from '../composables/useScanSoloRole';
import { serverErrorMessage } from '../scansoloErrors';

// UI-15: the contact's opt-out state, read from the server and shown to
// every user; only an administrator may clear it (CT-11), after confirming.
const props = defineProps({
  contactId: { type: Number, required: true },
});

const { t } = useI18n();
const { isAdministrator } = useScanSoloRole();

const optedOut = ref(null);
const loading = ref(false);
const loadError = ref(false);
const clearing = ref(false);
const showConfirm = ref(false);

const fetchOptOut = async () => {
  loading.value = true;
  loadError.value = false;
  try {
    const { data } = await ScanSoloContactsAPI.getOptOut(props.contactId);
    optedOut.value = data.opted_out;
  } catch (error) {
    loadError.value = true;
  } finally {
    loading.value = false;
  }
};

watch(() => props.contactId, fetchOptOut, { immediate: true });

const confirmClear = async () => {
  showConfirm.value = false;
  clearing.value = true;
  try {
    await ScanSoloContactsAPI.clearOptOut(props.contactId);
    await fetchOptOut();
    useAlert(t('SCANSOLO.CONTACT_OPT_OUT.SUCCESS'));
  } catch (error) {
    useAlert(serverErrorMessage(error, t('SCANSOLO.CONTACT_OPT_OUT.ERROR')));
  } finally {
    clearing.value = false;
  }
};
</script>

<template>
  <section
    data-testid="contact-opt-out-card"
    class="mx-2 my-3 rounded-lg border border-n-weak p-3 text-sm"
  >
    <h3 class="mb-1 font-medium text-n-slate-12">
      {{ t('SCANSOLO.CONTACT_OPT_OUT.TITLE') }}
    </h3>
    <ScanSoloListState
      :loading="loading"
      :error="loadError"
      @retry="fetchOptOut"
    >
      <p
        data-testid="contact-opt-out-state"
        :class="optedOut ? 'text-n-amber-11' : 'text-n-slate-11'"
      >
        {{
          optedOut
            ? t('SCANSOLO.CONTACT_OPT_OUT.OPTED_OUT')
            : t('SCANSOLO.CONTACT_OPT_OUT.NOT_OPTED_OUT')
        }}
      </p>
      <button
        v-if="isAdministrator && optedOut"
        type="button"
        data-testid="contact-opt-out-remove"
        :disabled="clearing"
        class="mt-2 rounded-lg border border-n-weak px-3 py-1.5 text-sm disabled:opacity-50"
        @click="showConfirm = true"
      >
        {{ t('SCANSOLO.CONTACT_OPT_OUT.REMOVE') }}
      </button>
    </ScanSoloListState>
    <ScanSoloConfirmDialog
      :show="showConfirm"
      :message="t('SCANSOLO.CONTACT_OPT_OUT.CONFIRM_MESSAGE')"
      :confirm-label="t('SCANSOLO.CONTACT_OPT_OUT.CONFIRM')"
      :cancel-label="t('SCANSOLO.CONTACT_OPT_OUT.CANCEL')"
      @confirm="confirmClear"
      @cancel="showConfirm = false"
    />
  </section>
</template>
