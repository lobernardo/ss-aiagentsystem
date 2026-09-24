<script setup>
import ScanSoloPageLayout from 'dashboard/routes/dashboard/scansolo/components/ScanSoloPageLayout.vue';
import { onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useScansoloProposalsStore } from 'dashboard/store/scansolo/proposals';

const { t } = useI18n();
const store = useScansoloProposalsStore();

const createCorrelationId = () =>
  globalThis.crypto?.randomUUID?.() ||
  `proposal-${Date.now()}-${Math.random().toString(36).slice(2)}`;

onMounted(() => {
  store.fetchProposals();
});

const generate = proposal =>
  store.generateProposal(proposal.opportunityId, createCorrelationId());

const approve = (proposal, version) =>
  store.approveProposal(proposal.id, version.id, createCorrelationId());

const send = (proposal, version) =>
  store.sendProposal(proposal.id, version.id, createCorrelationId());

const canSend = version =>
  version.status === 'generated' || version.status === 'approved';

const sendDisabled = version =>
  !canSend(version) || (version.approvalRequired && !version.approvedAt);

defineExpose({ generate, approve, send });
</script>

<template>
  <ScanSoloPageLayout>
    <div class="p-6 max-w-4xl mx-auto" data-testid="proposals-screen">
      <h1 class="text-xl font-medium text-n-slate-12 mb-4">
        {{ t('SCANSOLO.PROPOSALS.TITLE') }}
      </h1>

      <p
        v-if="!store.proposals.length"
        data-testid="proposals-empty-state"
        class="text-sm text-n-slate-10"
      >
        {{ t('SCANSOLO.PROPOSALS.EMPTY_STATE') }}
      </p>

      <div
        v-for="proposal in store.proposals"
        :key="proposal.id"
        data-testid="proposal-row"
        :data-proposal-id="proposal.id"
        class="rounded-lg border border-n-weak p-3 mb-3"
      >
        <div class="flex items-center justify-between mb-2">
          <p data-testid="proposal-contact-name" class="text-sm font-medium">
            {{ proposal.contactName }}
          </p>
          <button
            type="button"
            data-testid="generate-button"
            class="rounded-lg border border-n-weak px-3 py-1.5 text-sm"
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
          class="flex items-center justify-between rounded-lg bg-n-alpha-1 p-2 mb-1"
        >
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
              {{
                t(
                  `SCANSOLO.PROPOSALS.STATUSES.${version.status?.toUpperCase()}`
                )
              }}
            </span>
            <span
              v-if="version.approvedAt"
              data-testid="version-approved-badge"
              class="ms-2 text-xs font-medium px-2 py-0.5 rounded-full bg-n-teal-3 text-n-teal-11"
            >
              {{ t('SCANSOLO.PROPOSALS.APPROVED') }}
            </span>
          </div>

          <div v-if="version.isCurrent" class="flex items-center gap-2">
            <button
              v-if="version.status === 'generated' && !version.approvedAt"
              type="button"
              data-testid="approve-button"
              class="rounded-lg border border-n-weak px-3 py-1.5 text-sm"
              @click="approve(proposal, version)"
            >
              {{ t('SCANSOLO.PROPOSALS.APPROVE') }}
            </button>
            <button
              type="button"
              data-testid="send-button"
              :disabled="sendDisabled(version)"
              class="rounded-lg border border-n-weak px-3 py-1.5 text-sm disabled:opacity-50 disabled:cursor-not-allowed"
              @click="send(proposal, version)"
            >
              {{ t('SCANSOLO.PROPOSALS.SEND') }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </ScanSoloPageLayout>
</template>
