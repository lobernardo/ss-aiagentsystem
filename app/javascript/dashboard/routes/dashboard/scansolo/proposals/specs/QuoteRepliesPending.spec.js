import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import ScanSoloQuoteRepliesAPI from 'dashboard/api/scansoloQuoteReplies';
import ScanSoloPipelineOpportunitiesAPI from 'dashboard/api/scansoloPipelineOpportunities';
import QuoteRepliesPending from '../QuoteRepliesPending.vue';

vi.mock('dashboard/api/scansoloQuoteReplies', () => ({
  default: { getPending: vi.fn(), link: vi.fn(), discard: vi.fn() },
}));

vi.mock('dashboard/api/scansoloPipelineOpportunities', () => ({
  default: { get: vi.fn(), show: vi.fn() },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const push = vi.fn();
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1 } }),
  useRouter: () => ({ push }),
}));

withFullI18n();
enableAutoUnmount(afterEach);

const unmatchedReply = {
  id: 1,
  conversation_id: 50,
  message_id: 500,
  sender_email: 'luciano@scansolo.com.br',
  subject: 'Re: orçamento',
  received_at: '2026-01-05T12:00:00Z',
  excerpt: 'Segue o valor combinado.',
  kind: 'unmatched',
  quote_request_id: null,
};

const lateReply = {
  id: 2,
  conversation_id: 51,
  message_id: 501,
  sender_email: 'luciano@scansolo.com.br',
  subject: 'Solicitação de orçamento #8 — Solar Ltda',
  received_at: '2026-01-06T12:00:00Z',
  excerpt: 'Correção do valor.',
  kind: 'late_reply',
  quote_request_id: 4,
};

const opportunities = [
  {
    id: 8,
    contact_name: 'Ada Lovelace',
    company: 'Solar Ltda',
    stage: 'qualificado',
    quote_request_status: 'awaiting_reply',
  },
  {
    id: 9,
    contact_name: 'Grace Hopper',
    company: null,
    stage: 'qualificado',
    quote_request_status: 'correction_requested',
  },
  {
    id: 10,
    contact_name: 'Closed Lead',
    company: null,
    stage: 'proposta_enviada',
    quote_request_status: 'replied',
  },
];

const mountPending = async () => {
  const wrapper = mount(QuoteRepliesPending);
  await flushPromises();
  return wrapper;
};

const row = (wrapper, id) =>
  wrapper.find(`[data-testid="quote-reply-row"][data-reply-id="${id}"]`);

describe('QuoteRepliesPending', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    ScanSoloQuoteRepliesAPI.getPending.mockResolvedValue({
      data: [unmatchedReply, lateReply],
    });
    ScanSoloPipelineOpportunitiesAPI.get.mockResolvedValue({
      data: opportunities,
    });
  });

  it('lists one row per pending reply with sender, subject, date and excerpt', async () => {
    const wrapper = await mountPending();

    expect(wrapper.findAll('[data-testid="quote-reply-row"]')).toHaveLength(2);
    const unmatched = row(wrapper, 1);
    expect(unmatched.find('[data-testid="quote-reply-sender"]').text()).toBe(
      'Remetente: luciano@scansolo.com.br'
    );
    expect(unmatched.find('[data-testid="quote-reply-subject"]').text()).toBe(
      'Assunto: Re: orçamento'
    );
    expect(
      unmatched
        .find('[data-testid="quote-reply-received-at"]')
        .attributes('title')
    ).toBe('05/01/2026 12:00');
    expect(unmatched.find('[data-testid="quote-reply-excerpt"]').text()).toBe(
      'Trecho: Segue o valor combinado.'
    );
  });

  it('opens the e-mail conversation of a reply', async () => {
    const wrapper = await mountPending();

    await row(wrapper, 1)
      .find('[data-testid="quote-reply-conversation-link"]')
      .trigger('click');

    expect(push).toHaveBeenCalledWith({
      name: 'inbox_conversation',
      params: { accountId: 1, conversation_id: 50 },
    });
  });

  it('offers only the open quote requests to link an unmatched reply', async () => {
    const wrapper = await mountPending();

    const options = row(wrapper, 1)
      .findAll('[data-testid="quote-reply-link-select"] option:not([disabled])')
      .map(option => option.text());

    expect(options).toEqual(['#8 — Solar Ltda', '#9 — Grace Hopper']);
    expect(
      row(wrapper, 1)
        .find('[data-testid="quote-reply-link-button"]')
        .attributes('disabled')
    ).toBeDefined();
    expect(
      row(wrapper, 1)
        .find('[data-testid="quote-reply-discard-button"]')
        .exists()
    ).toBe(false);
  });

  it('links an unmatched reply with the right ids and removes the row', async () => {
    ScanSoloPipelineOpportunitiesAPI.show.mockResolvedValue({
      data: { id: 8, quote_request: { id: 3, status: 'awaiting_reply' } },
    });
    ScanSoloQuoteRepliesAPI.link.mockResolvedValue({
      data: { quote_request_id: 3, status: 'replied' },
    });
    const wrapper = await mountPending();
    const unmatched = row(wrapper, 1);

    await unmatched.find('[data-testid="quote-reply-link-select"]').setValue(8);
    await unmatched
      .find('[data-testid="quote-reply-link-button"]')
      .trigger('click');
    await flushPromises();

    expect(ScanSoloPipelineOpportunitiesAPI.show).toHaveBeenCalledWith(8);
    expect(ScanSoloQuoteRepliesAPI.link).toHaveBeenCalledWith(1, 3);
    expect(row(wrapper, 1).exists()).toBe(false);
    expect(wrapper.findAll('[data-testid="quote-reply-row"]')).toHaveLength(1);
    expect(useAlert).toHaveBeenCalledWith(
      'Resposta vinculada à solicitação de orçamento.'
    );
  });

  it('keeps the row and shows the i18n message on a 422', async () => {
    ScanSoloPipelineOpportunitiesAPI.show.mockResolvedValue({
      data: { id: 8, quote_request: { id: 3, status: 'awaiting_reply' } },
    });
    ScanSoloQuoteRepliesAPI.link.mockRejectedValue({
      response: { status: 422, data: { error: 'already_linked' } },
    });
    const wrapper = await mountPending();
    const unmatched = row(wrapper, 1);

    await unmatched.find('[data-testid="quote-reply-link-select"]').setValue(8);
    await unmatched
      .find('[data-testid="quote-reply-link-button"]')
      .trigger('click');
    await flushPromises();

    expect(row(wrapper, 1).exists()).toBe(true);
    expect(useAlert).toHaveBeenCalledWith('Esta resposta já foi vinculada.');
  });

  it('shows the origin request of a late reply and discards it after confirmation', async () => {
    ScanSoloQuoteRepliesAPI.discard.mockResolvedValue({ data: {} });
    const wrapper = await mountPending();
    const late = row(wrapper, 2);

    expect(late.find('[data-testid="quote-reply-origin"]').text()).toBe(
      'Solicitação de orçamento de origem #4'
    );
    expect(late.find('[data-testid="quote-reply-link-button"]').exists()).toBe(
      false
    );

    await late
      .find('[data-testid="quote-reply-discard-button"]')
      .trigger('click');
    expect(ScanSoloQuoteRepliesAPI.discard).not.toHaveBeenCalled();
    await wrapper
      .find('[data-testid="confirm-dialog-confirm"]')
      .trigger('click');
    await flushPromises();

    expect(ScanSoloQuoteRepliesAPI.discard).toHaveBeenCalledWith(2);
    expect(row(wrapper, 2).exists()).toBe(false);
    expect(useAlert).toHaveBeenCalledWith('Resposta descartada.');
  });

  it('shows the empty state without pending replies', async () => {
    ScanSoloQuoteRepliesAPI.getPending.mockResolvedValue({ data: [] });
    const wrapper = await mountPending();

    expect(wrapper.find('[data-testid="list-state-empty"]').text()).toBe(
      'Nenhuma resposta pendente de vínculo.'
    );
  });

  it('renders the error state when the list fails to load', async () => {
    ScanSoloQuoteRepliesAPI.getPending.mockRejectedValue(new Error('boom'));
    const wrapper = await mountPending();

    expect(wrapper.find('[data-testid="list-state-error"]').exists()).toBe(
      true
    );
  });
});
