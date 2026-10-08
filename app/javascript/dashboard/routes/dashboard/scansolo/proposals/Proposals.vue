<script setup>
import ScanSoloPageLayout from 'dashboard/routes/dashboard/scansolo/components/ScanSoloPageLayout.vue';
import ScanSoloListState from 'dashboard/routes/dashboard/scansolo/components/ScanSoloListState.vue';
import ScanSoloConfirmDialog from 'dashboard/routes/dashboard/scansolo/components/ScanSoloConfirmDialog.vue';
import TechnicalDetails from 'dashboard/routes/dashboard/scansolo/components/TechnicalDetails.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import QuoteRepliesPending from './QuoteRepliesPending.vue';
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useScansoloProposalsStore } from 'dashboard/store/scansolo/proposals';
import { useScansoloAiAgentConfigStore } from 'dashboard/store/scansolo/aiAgentConfig';
import { useScanSoloRole } from '../composables/useScanSoloRole';
import {
  DELIVERY_CHANNEL_STATUS_LABELS,
  PROPOSAL_ACTION_ERROR_LABELS,
  PROPOSAL_STATUS_LABELS,
  REASON_LABELS,
  commercialStatusKey,
  enumLabel,
} from '../scansoloLabels';
import { serverErrorMessage } from '../scansoloErrors';

const INTEGRATION_BLOCKED = 'blocked';
const INTEGRATION_NOT_CONFIGURED_ERROR = 'proposal_integration_not_configured';
const AWAITING_APPROVAL = 'awaiting_approval';

const { t } = useI18n();
const store = useScansoloProposalsStore();
const configStore = useScansoloAiAgentConfigStore();
const { canApproveProposals } = useScanSoloRole();

const loadError = ref(false);
// UI-09: a dead-letter reprocess asks for confirmation. { proposal, version }
const pendingReprocess = ref(null);
// UI-01: "Rejeitar" asks for a required reason. { proposal, version }
const pendingReject = ref(null);
const rejectReason = ref('');
const rejectDialog = ref(null);
const rejecting = ref(false);

const createCorrelationId = () =>
  globalThis.crypto?.randomUUID?.() ||
  `proposal-${Date.now()}-${Math.random().toString(36).slice(2)}`;

const loadProposals = async () => {
  loadError.value = false;
  try {
    await store.fetchProposals();
  } catch (error) {
    loadError.value = true;
  }
};

onMounted(() => {
  loadProposals();
  // CT-02: the published commercial user approves, rejects and retries too.
  if (!configStore.published) configStore.fetch().catch(() => {});
});

// UI-13: the integration state is the same for every proposal of the account.
const integrationBlocked = computed(() =>
  store.proposals.some(
    proposal => proposal.integrationState === INTEGRATION_BLOCKED
  )
);

const runMutation = async (mutation, successKey) => {
  try {
    await mutation();
    useAlert(t(successKey));
  } catch (error) {
    const actionErrorKey =
      PROPOSAL_ACTION_ERROR_LABELS[error?.response?.data?.error];
    if (actionErrorKey) {
      // Keys come from the static maps in scansoloLabels.
      // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
      useAlert(t(actionErrorKey));
      return;
    }
    const message = serverErrorMessage(
      error,
      t('SCANSOLO.COMMON.ACTION_ERROR')
    );
    useAlert(
      message === INTEGRATION_NOT_CONFIGURED_ERROR
        ? t('SCANSOLO.PROPOSALS.INTEGRATION_BLOCKED')
        : message
    );
  }
};

const generate = proposal =>
  runMutation(
    () => store.generateProposal(proposal.opportunityId, createCorrelationId()),
    'SCANSOLO.PROPOSALS.GENERATE_SUCCESS'
  );

const retry = (proposal, version, confirmReprocess) =>
  runMutation(
    () => store.retryProposal(proposal.id, version.id, confirmReprocess),
    'SCANSOLO.PROPOSALS.RETRY_SUCCESS'
  );

// UI-09: reprocessing a dead letter always asks first.
const requestRetry = (proposal, version) => {
  if (version.deadLetter) {
    pendingReprocess.value = { proposal, version };
  } else {
    retry(proposal, version, false);
  }
};

const confirmReprocess = async () => {
  const { proposal, version } = pendingReprocess.value;
  pendingReprocess.value = null;
  await retry(proposal, version, true);
};

const reprocessMessage = computed(() =>
  pendingReprocess.value
    ? t('SCANSOLO.PROPOSALS.REPROCESS_CONFIRM_MESSAGE', {
        count: pendingReprocess.value.version.retryCount,
      })
    : ''
);

// CT-02 / RF-15: administrators or the published commercial user approve,
// reject and retry ("Reenviar").
const canManage = computed(() =>
  canApproveProposals(configStore.published?.commercialUserId)
);

const showApprovalActions = version =>
  canManage.value && version.isCurrent && version.status === AWAITING_APPROVAL;

// RF-08 / Q1: no lead e-mail, or no stored PDF yet, keeps "Aprovar" disabled.
const approveBlocked = (proposal, version) =>
  !proposal.leadEmailPresent || !version.documentUrl;

const approveVersion = (proposal, version) =>
  runMutation(
    () => store.approveProposal(proposal.id, version.id, createCorrelationId()),
    'SCANSOLO.PROPOSALS.APPROVE_SUCCESS'
  );

const requestReject = (proposal, version) => {
  pendingReject.value = { proposal, version };
  rejectReason.value = '';
  rejectDialog.value.open();
};

const confirmReject = async () => {
  if (!rejectReason.value.trim() || rejecting.value) return;

  const { proposal, version } = pendingReject.value;
  rejecting.value = true;
  try {
    await runMutation(
      () => store.rejectProposal(proposal.id, version.id, rejectReason.value),
      'SCANSOLO.PROPOSALS.REJECT_SUCCESS'
    );
  } finally {
    rejecting.value = false;
    rejectDialog.value?.close();
  }
};

const resetReject = () => {
  pendingReject.value = null;
  rejectReason.value = '';
};

const leadDetailRoute = proposal => ({
  name: 'scansolo_pipeline_opportunity_detail',
  params: { opportunityId: proposal.opportunityId },
});

const hasDelivery = version =>
  !!(version.delivery?.emailStatus || version.delivery?.noticeStatus);

const quoteRequestStatusLabel = proposal => {
  const key = commercialStatusKey(proposal.quoteRequestStatus, null);
  // Keys come from the static maps in scansoloLabels.
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  return key ? t(key) : '';
};

// `valid_until` is a calendar date; UTC keeps it from shifting a day.
const formatDate = value =>
  new Intl.DateTimeFormat('pt-BR', { timeZone: 'UTC' }).format(new Date(value));

const versionTechnicalItems = version => [
  {
    label: t('SCANSOLO.TECHNICAL_DETAILS.PROPOSAL_VERSION_ID'),
    value: version.id,
  },
  {
    label: t('SCANSOLO.TECHNICAL_DETAILS.CORRELATION_ID'),
    value: version.correlationId,
  },
];

defineExpose({ generate, requestRetry, approveVersion, requestReject });
</script>

<template>
  <ScanSoloPageLayout>
    <div class="p-6 max-w-4xl mx-auto" data-testid="proposals-screen">
      <h1 class="text-xl font-medium text-n-slate-12 mb-4">
        {{ t('SCANSOLO.PROPOSALS.TITLE') }}
      </h1>

      <p
        v-if="integrationBlocked"
        data-testid="integration-blocked-notice"
        class="rounded-lg border border-n-amber-6 bg-n-amber-2 px-3 py-2 text-sm text-n-amber-11 mb-4"
      >
        {{ t('SCANSOLO.PROPOSALS.INTEGRATION_BLOCKED') }}
      </p>

      <QuoteRepliesPending />

      <ScanSoloListState
        :loading="store.uiFlags.fetchingList"
        :error="loadError"
        :empty="!store.proposals.length"
        :empty-message="t('SCANSOLO.PROPOSALS.EMPTY_STATE')"
        @retry="loadProposals"
      >
        <div
          v-for="proposal in store.proposals"
          :key="proposal.id"
          data-testid="proposal-row"
          :data-proposal-id="proposal.id"
          class="rounded-lg border border-n-weak p-3 mb-3"
        >
          <div class="flex items-center justify-between mb-2">
            <div>
              <p
                data-testid="proposal-contact-name"
                class="text-sm font-medium"
              >
                {{ proposal.contactName }}
              </p>
              <p
                v-if="quoteRequestStatusLabel(proposal)"
                data-testid="proposal-quote-request-status"
                class="text-xs text-n-slate-11"
              >
                {{ t('SCANSOLO.PROPOSALS.QUOTE_REQUEST_STATUS_LABEL') }}:
                {{ quoteRequestStatusLabel(proposal) }}
              </p>
            </div>
            <button
              type="button"
              data-testid="generate-button"
              :disabled="integrationBlocked"
              class="rounded-lg border border-n-weak px-3 py-1.5 text-sm disabled:opacity-50 disabled:cursor-not-allowed"
              @click="generate(proposal)"
            >
              {{ t('SCANSOLO.PROPOSALS.GENERATE') }}
            </button>
          </div>

          <div
            v-for="version in proposal.versions"
            :key="version.id"
            data-testid="proposal-version-row"
            :data-version-id="version.id"
            class="rounded-lg bg-n-alpha-1 p-2 mb-1"
          >
            <div class="flex items-center justify-between">
              <div>
                <span data-testid="version-number" class="text-xs font-medium">
                  {{ t('SCANSOLO.PROPOSALS.VERSION_LABEL') }}
                  {{ version.versionNumber }}
                </span>
                <span
                  data-testid="version-current-badge"
                  class="ms-2 text-xs font-medium px-2 py-0.5 rounded-full bg-n-slate-3 text-n-slate-11"
                >
                  {{
                    version.isCurrent
                      ? t('SCANSOLO.PROPOSALS.CURRENT')
                      : t('SCANSOLO.PROPOSALS.NON_CURRENT')
                  }}
                </span>
                <span
                  data-testid="version-status"
                  class="ms-2 text-xs font-medium px-2 py-0.5 rounded-full bg-n-slate-3 text-n-slate-11"
                >
                  {{ enumLabel(t, PROPOSAL_STATUS_LABELS, version.status) }}
                </span>
                <span
                  v-if="version.approvedAt"
                  data-testid="version-approved-badge"
                  class="ms-2 text-xs font-medium px-2 py-0.5 rounded-full bg-n-teal-3 text-n-teal-11"
                >
                  {{ t('SCANSOLO.PROPOSALS.APPROVED') }}
                </span>
                <span
                  v-if="version.deadLetter"
                  data-testid="version-dead-letter-badge"
                  class="ms-2 text-xs font-medium px-2 py-0.5 rounded-full bg-n-ruby-3 text-n-ruby-11"
                >
                  {{ t('SCANSOLO.PROPOSALS.DEAD_LETTER') }}
                </span>
              </div>

              <div v-if="version.isCurrent" class="flex items-center gap-2">
                <template v-if="showApprovalActions(version)">
                  <button
                    type="button"
                    data-testid="approve-button"
                    :disabled="approveBlocked(proposal, version)"
                    class="rounded-lg bg-n-brand px-3 py-1.5 text-sm text-white disabled:opacity-50 disabled:cursor-not-allowed"
                    @click="approveVersion(proposal, version)"
                  >
                    {{ t('SCANSOLO.PROPOSALS.APPROVE') }}
                  </button>
                  <button
                    type="button"
                    data-testid="reject-button"
                    class="rounded-lg border border-n-weak px-3 py-1.5 text-sm"
                    @click="requestReject(proposal, version)"
                  >
                    {{ t('SCANSOLO.PROPOSALS.REJECT') }}
                  </button>
                </template>
                <button
                  v-if="canManage && version.status === 'failed'"
                  type="button"
                  data-testid="retry-button"
                  :disabled="integrationBlocked"
                  class="rounded-lg border border-n-weak px-3 py-1.5 text-sm disabled:opacity-50 disabled:cursor-not-allowed"
                  @click="requestRetry(proposal, version)"
                >
                  {{
                    version.deadLetter
                      ? t('SCANSOLO.PROPOSALS.REPROCESS')
                      : t('SCANSOLO.PROPOSALS.RESEND')
                  }}
                </button>
              </div>
            </div>
            <p
              v-if="version.proposalNumber || version.validUntil"
              class="mt-1 text-xs text-n-slate-11"
            >
              <span
                v-if="version.proposalNumber"
                data-testid="version-proposal-number"
              >
                {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.PROPOSAL.NUMBER_LABEL') }}:
                {{ version.proposalNumber }}
              </span>
              <span
                v-if="version.validUntil"
                data-testid="version-valid-until"
                class="ms-2"
              >
                {{
                  t(
                    'SCANSOLO.PIPELINE_BOARD.DETAIL.PROPOSAL.VALID_UNTIL_LABEL'
                  )
                }}:
                {{ formatDate(version.validUntil) }}
              </span>
            </p>
            <a
              v-if="version.documentUrl || version.artifactUrl"
              data-testid="version-document-link"
              :href="version.documentUrl || version.artifactUrl"
              target="_blank"
              rel="noopener noreferrer"
              class="mt-1 inline-block text-xs text-n-blue-text underline"
            >
              {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.PROPOSAL.DOCUMENT_LINK') }}
            </a>
            <template v-if="showApprovalActions(version)">
              <p
                v-if="!proposal.leadEmailPresent"
                data-testid="lead-email-missing-notice"
                class="mt-1 text-xs text-n-amber-11"
              >
                {{ t('SCANSOLO.PROPOSALS.LEAD_EMAIL_MISSING') }}
                <router-link
                  data-testid="lead-detail-link"
                  :to="leadDetailRoute(proposal)"
                  class="ms-1 text-n-blue-text underline"
                >
                  {{ t('SCANSOLO.PROPOSALS.LEAD_EMAIL_LINK') }}
                </router-link>
              </p>
              <p
                v-if="!version.documentUrl"
                data-testid="document-pending-notice"
                class="mt-1 text-xs text-n-slate-11"
              >
                {{ t('SCANSOLO.PROPOSALS.DOCUMENT_PENDING') }}
              </p>
            </template>
            <p
              v-if="version.status === 'rejected' && version.rejectionReason"
              data-testid="version-rejection-reason"
              class="mt-1 text-xs text-n-slate-11"
            >
              {{ t('SCANSOLO.PROPOSALS.REJECTION_REASON_LABEL') }}:
              {{ version.rejectionReason }}
            </p>
            <p
              v-if="version.status === 'failed' && version.failureReason"
              data-testid="version-failure-reason"
              class="mt-1 text-xs text-n-ruby-11"
            >
              {{ t('SCANSOLO.PROPOSALS.FAILURE_REASON_LABEL') }}:
              {{ enumLabel(t, REASON_LABELS, version.failureReason) }}
            </p>
            <p
              v-if="hasDelivery(version)"
              data-testid="version-delivery"
              class="mt-1 text-xs text-n-slate-11"
            >
              {{ t('SCANSOLO.PROPOSALS.DELIVERY.TITLE') }}:
              <span
                v-if="version.delivery.emailStatus"
                data-testid="version-delivery-email"
              >
                {{ t('SCANSOLO.PROPOSALS.DELIVERY.EMAIL_LABEL') }}
                {{
                  enumLabel(
                    t,
                    DELIVERY_CHANNEL_STATUS_LABELS,
                    version.delivery.emailStatus
                  )
                }}
              </span>
              <span
                v-if="version.delivery.noticeStatus"
                data-testid="version-delivery-notice"
                class="ms-2"
              >
                {{ t('SCANSOLO.PROPOSALS.DELIVERY.NOTICE_LABEL') }}
                {{
                  enumLabel(
                    t,
                    DELIVERY_CHANNEL_STATUS_LABELS,
                    version.delivery.noticeStatus
                  )
                }}
              </span>
            </p>
            <TechnicalDetails :items="versionTechnicalItems(version)" />
          </div>
        </div>
      </ScanSoloListState>

      <Dialog
        ref="rejectDialog"
        :title="t('SCANSOLO.PROPOSALS.REJECT_DIALOG.TITLE')"
        :description="t('SCANSOLO.PROPOSALS.REJECT_DIALOG.DESCRIPTION')"
        :confirm-button-label="t('SCANSOLO.PROPOSALS.REJECT_DIALOG.CONFIRM')"
        :disable-confirm-button="!rejectReason.trim()"
        :is-loading="rejecting"
        type="alert"
        @confirm="confirmReject"
        @close="resetReject"
      >
        <label class="block text-sm text-n-slate-11">
          {{ t('SCANSOLO.PROPOSALS.REJECT_DIALOG.REASON_LABEL') }}
          <textarea
            v-model="rejectReason"
            data-testid="reject-reason-input"
            rows="3"
            :placeholder="
              t('SCANSOLO.PROPOSALS.REJECT_DIALOG.REASON_PLACEHOLDER')
            "
            class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2 text-sm"
          />
        </label>
      </Dialog>

      <ScanSoloConfirmDialog
        :show="!!pendingReprocess"
        :message="reprocessMessage"
        :confirm-label="t('SCANSOLO.PROPOSALS.REPROCESS_CONFIRM')"
        @confirm="confirmReprocess"
        @cancel="pendingReprocess = null"
      />
    </div>
  </ScanSoloPageLayout>
</template>
