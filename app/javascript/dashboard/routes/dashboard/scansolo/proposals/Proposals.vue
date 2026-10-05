<script setup>
import ScanSoloPageLayout from 'dashboard/routes/dashboard/scansolo/components/ScanSoloPageLayout.vue';
import ScanSoloListState from 'dashboard/routes/dashboard/scansolo/components/ScanSoloListState.vue';
import ScanSoloConfirmDialog from 'dashboard/routes/dashboard/scansolo/components/ScanSoloConfirmDialog.vue';
import TechnicalDetails from 'dashboard/routes/dashboard/scansolo/components/TechnicalDetails.vue';
import QuoteRepliesPending from './QuoteRepliesPending.vue';
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useScansoloProposalsStore } from 'dashboard/store/scansolo/proposals';
import { useScanSoloRole } from '../composables/useScanSoloRole';
import {
  PROPOSAL_STATUS_LABELS,
  REASON_LABELS,
  commercialStatusKey,
  enumLabel,
} from '../scansoloLabels';
import { serverErrorMessage } from '../scansoloErrors';

const INTEGRATION_BLOCKED = 'blocked';
const INTEGRATION_NOT_CONFIGURED_ERROR = 'proposal_integration_not_configured';

const { t } = useI18n();
const store = useScansoloProposalsStore();
const { isAdministrator } = useScanSoloRole();

const loadError = ref(false);
// RF-55 Etapa 1 / UI-06: only a dead-letter reprocess asks for confirmation;
// approving and sending are no longer offered by this screen.
// { proposal, version }
const pendingReprocess = ref(null);

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

onMounted(loadProposals);

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

// RF-48 / UI-13: retry (CT-10 "Reenviar") stays administrator-only.
const canRetry = () => isAdministrator.value;

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

defineExpose({ generate, requestRetry });
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
                <button
                  v-if="canRetry() && version.status === 'failed'"
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
            <p
              v-if="version.status === 'failed' && version.failureReason"
              data-testid="version-failure-reason"
              class="mt-1 text-xs text-n-ruby-11"
            >
              {{ t('SCANSOLO.PROPOSALS.FAILURE_REASON_LABEL') }}:
              {{ enumLabel(t, REASON_LABELS, version.failureReason) }}
            </p>
            <TechnicalDetails :items="versionTechnicalItems(version)" />
          </div>
        </div>
      </ScanSoloListState>

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
