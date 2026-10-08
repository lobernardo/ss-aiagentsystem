<script setup>
import ScanSoloPageLayout from 'dashboard/routes/dashboard/scansolo/components/ScanSoloPageLayout.vue';
import ScanSoloListState from 'dashboard/routes/dashboard/scansolo/components/ScanSoloListState.vue';
import ScanSoloTime from 'dashboard/routes/dashboard/scansolo/components/ScanSoloTime.vue';
import TechnicalDetails from 'dashboard/routes/dashboard/scansolo/components/TechnicalDetails.vue';
import { computed, onMounted, ref } from 'vue';
import camelcaseKeys from 'camelcase-keys';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store.js';
import Button from 'dashboard/components-next/button/Button.vue';
import ScanSoloPipelineOpportunitiesAPI from 'dashboard/api/scansoloPipelineOpportunities';
import { useScansoloPipelineOpportunitiesStore } from 'dashboard/store/scansolo/pipelineOpportunities';
import { useScanSoloRole } from '../composables/useScanSoloRole';
import {
  FIELD_STATUS_LABELS,
  INITIAL_TEMPLATE_FAILURE_STATUS_LABELS,
  LEAD_EMAIL_ERROR_LABELS,
  LEAD_SOURCE_LABELS,
  PROPOSAL_STATUS_LABELS,
  QUOTE_REQUEST_RESEND_ERROR_LABELS,
  REASON_LABELS,
  STAGE_LABELS,
  commercialStatusKey,
  enumLabel,
} from '../scansoloLabels';

// UI-04: value and validity only mean something once the PDF exists.
const PROPOSAL_STATUSES_WITH_TERMS = [
  'generated',
  'awaiting_approval',
  'approved',
  'sent',
];
const FIELD_STATUSES = Object.keys(FIELD_STATUS_LABELS);

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const vuexStore = useStore();
const agents = useMapGetter('agents/getAgents');
const { isAdministrator } = useScanSoloRole();
const opportunitiesStore = useScansoloPipelineOpportunitiesStore();

const opportunity = ref(null);
const loading = ref(false);
const loadError = ref(false);
const resendingQuoteRequest = ref(false);
// UI-02 / CT-09: inline edit of the lead e-mail.
const editingLeadEmail = ref(false);
const leadEmailDraft = ref('');
const leadEmailError = ref('');
const savingLeadEmail = ref(false);

// UI-02: contact and conversation come straight off the opportunity payload
// (T13's serializer now embeds contact_name/stage_history for this view);
// no separate fetch is needed.
const fetchOpportunity = async () => {
  // A reload after an action keeps the screen on display.
  loading.value = !opportunity.value;
  loadError.value = false;
  try {
    const { data } = await ScanSoloPipelineOpportunitiesAPI.show(
      route.params.opportunityId
    );
    opportunity.value = camelcaseKeys(data, { deep: true });
  } catch (error) {
    loadError.value = true;
  } finally {
    loading.value = false;
  }
};

const goToConversation = () => {
  if (!opportunity.value) return;

  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: route.params.accountId,
      conversation_id: opportunity.value.conversationId,
    },
  });
};

const stageLabel = stage =>
  stage
    ? enumLabel(t, STAGE_LABELS, stage)
    : t('SCANSOLO.PIPELINE_BOARD.DETAIL.INITIAL_STAGE');

const leadSourceLabel = computed(() =>
  enumLabel(t, LEAD_SOURCE_LABELS, opportunity.value.leadSource || 'none')
);

const ownerLabel = computed(() => {
  const { ownerId } = opportunity.value;
  if (!ownerId) return t('SCANSOLO.PIPELINE_BOARD.UNASSIGNED_OWNER');
  const owner = (agents.value || []).find(agent => agent.id === ownerId);
  return owner?.name || t('SCANSOLO.PIPELINE_BOARD.ASSIGNED_OWNER');
});

// RF-45: display-only grouping of the lead-state fields by classification.
const fieldsByStatus = computed(() => {
  const groups = Object.fromEntries(FIELD_STATUSES.map(status => [status, []]));
  Object.values(opportunity.value.leadState?.blocks || {})
    .flat()
    .forEach(field => groups[field.status]?.push(field));
  return groups;
});

// A missing field has no value; the others read "Label: value".
const fieldText = field => {
  if (field.status === 'faltante') return field.label;
  const value = Array.isArray(field.value)
    ? field.value.join(', ')
    : field.value;
  return `${field.label}: ${value ?? ''}`;
};

const statusLabel = key =>
  // Keys come from the static maps in scansoloLabels.
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  key ? t(key) : '';

const commercialStatusLabel = computed(() =>
  statusLabel(
    commercialStatusKey(
      opportunity.value.quoteRequestStatus,
      opportunity.value.proposalStatus
    )
  )
);

const quoteRequestStatusLabel = computed(() =>
  statusLabel(commercialStatusKey(opportunity.value.quoteRequest?.status, null))
);

const showProposalTerms = computed(() =>
  PROPOSAL_STATUSES_WITH_TERMS.includes(opportunity.value.proposal?.status)
);

const formatMoney = (value, currency) =>
  new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: currency || 'BRL',
  }).format(Number(value));

// `valid_until` is a calendar date; UTC keeps it from shifting a day.
const formatDate = value =>
  new Intl.DateTimeFormat('pt-BR', { timeZone: 'UTC' }).format(new Date(value));

// UI-07: administrators only, and only when CT-12 would accept it.
const canResendQuoteRequest = computed(
  () => isAdministrator.value && opportunity.value.quoteRequestResendAvailable
);

const resendQuoteRequest = async () => {
  resendingQuoteRequest.value = true;
  try {
    await ScanSoloPipelineOpportunitiesAPI.resendQuoteRequest(
      opportunity.value.id
    );
    useAlert(t('SCANSOLO.PIPELINE_BOARD.DETAIL.RESEND_QUOTE_REQUEST.SUCCESS'));
    await fetchOpportunity();
  } catch (error) {
    useAlert(
      enumLabel(
        t,
        QUOTE_REQUEST_RESEND_ERROR_LABELS,
        error?.response?.data?.error
      ) || t('SCANSOLO.COMMON.ACTION_ERROR')
    );
  } finally {
    resendingQuoteRequest.value = false;
  }
};

const startEditingLeadEmail = () => {
  leadEmailDraft.value = opportunity.value.leadEmail || '';
  leadEmailError.value = '';
  editingLeadEmail.value = true;
};

const cancelEditingLeadEmail = () => {
  editingLeadEmail.value = false;
  leadEmailError.value = '';
};

const saveLeadEmail = async () => {
  savingLeadEmail.value = true;
  leadEmailError.value = '';
  try {
    const updated = await opportunitiesStore.updateLeadEmail(
      opportunity.value.id,
      leadEmailDraft.value.trim()
    );
    opportunity.value.leadEmail = updated.leadEmail;
    editingLeadEmail.value = false;
    useAlert(t('SCANSOLO.PIPELINE_BOARD.DETAIL.LEAD_EMAIL.SUCCESS'));
  } catch (error) {
    leadEmailError.value =
      enumLabel(t, LEAD_EMAIL_ERROR_LABELS, error?.response?.data?.error) ||
      t('SCANSOLO.COMMON.ACTION_ERROR');
  } finally {
    savingLeadEmail.value = false;
  }
};

const technicalItems = computed(() => [
  { label: t('SCANSOLO.TECHNICAL_DETAILS.ID'), value: opportunity.value.id },
  {
    label: t('SCANSOLO.TECHNICAL_DETAILS.OWNER_ID'),
    value: opportunity.value.ownerId,
  },
  {
    label: t('SCANSOLO.TECHNICAL_DETAILS.CONTACT_ID'),
    value: opportunity.value.contactId,
  },
  {
    label: t('SCANSOLO.TECHNICAL_DETAILS.CONVERSATION_ID'),
    value: opportunity.value.conversationId,
  },
  {
    label: t('SCANSOLO.TECHNICAL_DETAILS.RAW_PAYLOAD'),
    value: opportunity.value.stageHistory,
  },
]);

onMounted(() => {
  vuexStore.dispatch('agents/get');
  fetchOpportunity();
});

defineExpose({
  fetchOpportunity,
  goToConversation,
  resendQuoteRequest,
  saveLeadEmail,
});
</script>

<template>
  <ScanSoloPageLayout>
    <div class="p-4">
      <ScanSoloListState
        :loading="loading"
        :error="loadError"
        @retry="fetchOpportunity"
      >
        <div v-if="opportunity">
          <h2 class="text-n-slate-12 text-lg font-medium mb-4">
            {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.TITLE') }}
          </h2>

          <section data-testid="opportunity-contact" class="mb-4">
            <h3 class="text-n-slate-11 text-sm font-medium">
              {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.CONTACT_LABEL') }}
            </h3>
            <p data-testid="opportunity-contact-name">
              {{ opportunity.contactName }}
            </p>
            <p data-testid="opportunity-stage" class="text-sm text-n-slate-11">
              {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.STAGE_LABEL') }}:
              {{ stageLabel(opportunity.stage) }}
            </p>
            <p class="text-sm text-n-slate-11">
              {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.LAST_INTERACTION_LABEL') }}:
              <ScanSoloTime
                :value="opportunity.lastCustomerInteractionAt"
                :fallback="t('SCANSOLO.COMMON.NOT_AVAILABLE')"
              />
            </p>
            <p
              data-testid="opportunity-lead-source"
              class="text-sm text-n-slate-11"
            >
              {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.LEAD_SOURCE_LABEL') }}:
              {{ leadSourceLabel }}
            </p>
            <p data-testid="opportunity-owner" class="text-sm text-n-slate-11">
              {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.OWNER_LABEL') }}:
              {{ ownerLabel }}
            </p>
            <p
              v-if="commercialStatusLabel"
              data-testid="opportunity-commercial-status"
              class="text-sm font-medium text-n-blue-11"
            >
              {{ commercialStatusLabel }}
            </p>
          </section>

          <section data-testid="opportunity-lead-email" class="mb-4">
            <div class="flex items-center justify-between mb-2">
              <h3 class="text-n-slate-11 text-sm font-medium">
                {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.LEAD_EMAIL.TITLE') }}
              </h3>
              <Button
                v-if="!editingLeadEmail"
                type="button"
                size="sm"
                variant="outline"
                data-testid="lead-email-edit-button"
                :label="t('SCANSOLO.PIPELINE_BOARD.DETAIL.LEAD_EMAIL.EDIT')"
                @click="startEditingLeadEmail"
              />
            </div>
            <form
              v-if="editingLeadEmail"
              data-testid="lead-email-form"
              class="flex flex-col gap-2"
              @submit.prevent="saveLeadEmail"
            >
              <label class="block text-sm text-n-slate-11">
                {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.LEAD_EMAIL.LABEL') }}
                <input
                  v-model="leadEmailDraft"
                  type="email"
                  data-testid="lead-email-input"
                  :placeholder="
                    t('SCANSOLO.PIPELINE_BOARD.DETAIL.LEAD_EMAIL.PLACEHOLDER')
                  "
                  class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2 text-sm"
                />
              </label>
              <p
                v-if="leadEmailError"
                data-testid="lead-email-error"
                class="text-xs text-n-ruby-11"
              >
                {{ leadEmailError }}
              </p>
              <div class="flex items-center gap-2">
                <Button
                  type="submit"
                  size="sm"
                  data-testid="lead-email-save-button"
                  :is-loading="savingLeadEmail"
                  :disabled="savingLeadEmail || !leadEmailDraft.trim()"
                  :label="t('SCANSOLO.PIPELINE_BOARD.DETAIL.LEAD_EMAIL.SAVE')"
                />
                <Button
                  type="button"
                  size="sm"
                  variant="faded"
                  color="slate"
                  data-testid="lead-email-cancel-button"
                  :label="t('SCANSOLO.PIPELINE_BOARD.DETAIL.LEAD_EMAIL.CANCEL')"
                  @click="cancelEditingLeadEmail"
                />
              </div>
            </form>
            <p
              v-else-if="opportunity.leadEmail"
              data-testid="lead-email-value"
              class="text-sm text-n-slate-12"
            >
              {{ opportunity.leadEmail }}
            </p>
            <p
              v-if="!opportunity.leadEmail"
              data-testid="lead-email-missing-notice"
              class="mt-1 rounded-lg border border-n-amber-6 bg-n-amber-2 px-3 py-2 text-sm text-n-amber-11"
            >
              {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.LEAD_EMAIL.MISSING') }}
            </p>
          </section>

          <section
            v-if="opportunity.initialTemplateFailure"
            data-testid="initial-template-failure"
            class="mb-4 rounded-lg border border-n-ruby-6 bg-n-ruby-2 px-3 py-2 text-sm text-n-ruby-11"
          >
            <h3 class="font-medium">
              {{
                t(
                  'SCANSOLO.PIPELINE_BOARD.DETAIL.INITIAL_TEMPLATE_FAILURE.TITLE'
                )
              }}
            </h3>
            <p data-testid="initial-template-failure-reason">
              {{
                t(
                  'SCANSOLO.PIPELINE_BOARD.DETAIL.INITIAL_TEMPLATE_FAILURE.REASON_LABEL'
                )
              }}:
              {{
                enumLabel(
                  t,
                  REASON_LABELS,
                  opportunity.initialTemplateFailure.reason
                )
              }}
            </p>
            <p data-testid="initial-template-failure-status">
              {{
                t(
                  'SCANSOLO.PIPELINE_BOARD.DETAIL.INITIAL_TEMPLATE_FAILURE.STATUS_LABEL'
                )
              }}:
              {{
                enumLabel(
                  t,
                  INITIAL_TEMPLATE_FAILURE_STATUS_LABELS,
                  opportunity.initialTemplateFailure.status
                )
              }}
            </p>
          </section>

          <section data-testid="opportunity-qualification" class="mb-4">
            <h3 class="text-n-slate-11 text-sm font-medium mb-2">
              {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.QUALIFICATION_TITLE') }}
            </h3>
            <div class="grid gap-3 md:grid-cols-3">
              <div
                v-for="status in FIELD_STATUSES"
                :key="status"
                :data-testid="`qualification-${status}`"
              >
                <h4 class="text-sm font-medium text-n-slate-12 mb-1">
                  {{ enumLabel(t, FIELD_STATUS_LABELS, status) }}
                </h4>
                <p
                  v-if="!fieldsByStatus[status].length"
                  class="text-xs text-n-slate-10"
                >
                  {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.QUALIFICATION_EMPTY') }}
                </p>
                <ul v-else class="text-xs text-n-slate-11">
                  <li
                    v-for="field in fieldsByStatus[status]"
                    :key="field.key"
                    data-testid="qualification-field"
                    :data-field-key="field.key"
                  >
                    {{ fieldText(field) }}
                  </li>
                </ul>
              </div>
            </div>
          </section>

          <section data-testid="opportunity-quote-request" class="mb-4">
            <div class="flex items-center justify-between mb-2">
              <h3 class="text-n-slate-11 text-sm font-medium">
                {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.QUOTE_REQUEST.TITLE') }}
              </h3>
              <Button
                v-if="canResendQuoteRequest"
                type="button"
                size="sm"
                variant="outline"
                data-testid="resend-quote-request-button"
                :is-loading="resendingQuoteRequest"
                :disabled="resendingQuoteRequest"
                :label="
                  t(
                    'SCANSOLO.PIPELINE_BOARD.DETAIL.RESEND_QUOTE_REQUEST.ACTION'
                  )
                "
                @click="resendQuoteRequest"
              />
            </div>
            <div
              v-if="opportunity.quoteRequest"
              class="text-sm text-n-slate-11"
            >
              <p data-testid="quote-request-status">
                {{
                  t(
                    'SCANSOLO.PIPELINE_BOARD.DETAIL.QUOTE_REQUEST.STATUS_LABEL'
                  )
                }}:
                {{ quoteRequestStatusLabel }}
              </p>
              <p>
                {{
                  t(
                    'SCANSOLO.PIPELINE_BOARD.DETAIL.QUOTE_REQUEST.SENT_AT_LABEL'
                  )
                }}:
                <ScanSoloTime
                  data-testid="quote-request-sent-at"
                  :value="opportunity.quoteRequest.sentAt"
                  :fallback="t('SCANSOLO.COMMON.NOT_AVAILABLE')"
                />
              </p>
              <p>
                {{
                  t(
                    'SCANSOLO.PIPELINE_BOARD.DETAIL.QUOTE_REQUEST.REPLIED_AT_LABEL'
                  )
                }}:
                <ScanSoloTime
                  data-testid="quote-request-replied-at"
                  :value="opportunity.quoteRequest.repliedAt"
                  :fallback="t('SCANSOLO.COMMON.NOT_AVAILABLE')"
                />
              </p>
            </div>
            <p
              v-else
              data-testid="quote-request-none"
              class="text-sm text-n-slate-10"
            >
              {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.QUOTE_REQUEST.NONE') }}
            </p>
          </section>

          <section data-testid="opportunity-proposal" class="mb-4">
            <h3 class="text-n-slate-11 text-sm font-medium mb-2">
              {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.PROPOSAL.TITLE') }}
            </h3>
            <div v-if="opportunity.proposal" class="text-sm text-n-slate-11">
              <p data-testid="proposal-version">
                {{
                  t('SCANSOLO.PIPELINE_BOARD.DETAIL.PROPOSAL.VERSION_LABEL')
                }}:
                {{ opportunity.proposal.versionNumber }}
              </p>
              <p
                v-if="opportunity.proposal.proposalNumber"
                data-testid="proposal-number"
              >
                {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.PROPOSAL.NUMBER_LABEL') }}:
                {{ opportunity.proposal.proposalNumber }}
              </p>
              <p data-testid="proposal-status">
                {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.PROPOSAL.STATUS_LABEL') }}:
                {{
                  enumLabel(
                    t,
                    PROPOSAL_STATUS_LABELS,
                    opportunity.proposal.status
                  )
                }}
              </p>
              <p
                v-if="
                  opportunity.proposal.status === 'rejected' &&
                  opportunity.proposal.rejectionReason
                "
                data-testid="proposal-rejection-reason"
              >
                {{
                  t(
                    'SCANSOLO.PIPELINE_BOARD.DETAIL.PROPOSAL.REJECTION_REASON_LABEL'
                  )
                }}:
                {{ opportunity.proposal.rejectionReason }}
              </p>
              <template v-if="showProposalTerms">
                <p
                  v-if="opportunity.proposal.value !== null"
                  data-testid="proposal-value"
                >
                  {{
                    t('SCANSOLO.PIPELINE_BOARD.DETAIL.PROPOSAL.VALUE_LABEL')
                  }}:
                  {{
                    formatMoney(
                      opportunity.proposal.value,
                      opportunity.proposal.currency
                    )
                  }}
                </p>
                <p
                  v-if="opportunity.proposal.validUntil"
                  data-testid="proposal-valid-until"
                >
                  {{
                    t(
                      'SCANSOLO.PIPELINE_BOARD.DETAIL.PROPOSAL.VALID_UNTIL_LABEL'
                    )
                  }}:
                  {{ formatDate(opportunity.proposal.validUntil) }}
                </p>
              </template>
              <a
                v-if="opportunity.proposal.documentUrl"
                data-testid="proposal-document-link"
                :href="opportunity.proposal.documentUrl"
                target="_blank"
                rel="noopener noreferrer"
                class="text-n-blue-text underline"
              >
                {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.PROPOSAL.DOCUMENT_LINK') }}
              </a>
            </div>
            <p
              v-else
              data-testid="proposal-none"
              class="text-sm text-n-slate-10"
            >
              {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.PROPOSAL.NONE') }}
            </p>
          </section>

          <button
            type="button"
            data-testid="opportunity-conversation-link"
            class="mb-4 text-n-blue-text underline"
            @click="goToConversation"
          >
            {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.CONVERSATION_LINK') }}
          </button>

          <section>
            <h3 class="text-n-slate-11 text-sm font-medium mb-2">
              {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.HISTORY_TITLE') }}
            </h3>
            <p
              v-if="!opportunity.stageHistory.length"
              data-testid="opportunity-history-empty"
            >
              {{ t('SCANSOLO.PIPELINE_BOARD.DETAIL.HISTORY_EMPTY') }}
            </p>
            <ul v-else data-testid="opportunity-history-list">
              <li
                v-for="event in opportunity.stageHistory"
                :key="event.id"
                data-testid="opportunity-history-item"
                class="text-sm"
              >
                <span data-testid="history-from-stage">{{
                  stageLabel(event.fromStage)
                }}</span>
                <span
                  class="i-lucide-arrow-right inline-block size-3 align-middle"
                  aria-hidden="true"
                />
                <span data-testid="history-to-stage">{{
                  stageLabel(event.toStage)
                }}</span>
                ·
                <ScanSoloTime
                  data-testid="history-created-at"
                  :value="event.createdAt"
                />
              </li>
            </ul>
          </section>

          <TechnicalDetails :items="technicalItems" />
        </div>
      </ScanSoloListState>
    </div>
  </ScanSoloPageLayout>
</template>
