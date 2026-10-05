import { setActivePinia, createPinia } from 'pinia';
import ScanSoloQuoteRepliesAPI from 'dashboard/api/scansoloQuoteReplies';
import { useScansoloQuoteRepliesStore } from '../quoteReplies';

vi.mock('dashboard/api/scansoloQuoteReplies', () => ({
  default: {
    getPending: vi.fn(),
    link: vi.fn(),
    discard: vi.fn(),
  },
}));

const unmatchedReply = {
  id: 11,
  conversation_id: 40,
  message_id: 400,
  sender_email: 'luciano@scansolo.com.br',
  subject: 'Re: orçamento',
  received_at: '2026-10-01T12:00:00Z',
  excerpt: 'Segue o orçamento',
  kind: 'unmatched',
  quote_request_id: null,
};

const lateReply = {
  ...unmatchedReply,
  id: 12,
  message_id: 401,
  kind: 'late_reply',
  quote_request_id: 3,
};

describe('useScansoloQuoteRepliesStore', () => {
  let store;

  beforeEach(async () => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    store = useScansoloQuoteRepliesStore();
    ScanSoloQuoteRepliesAPI.getPending.mockResolvedValue({
      data: [unmatchedReply, lateReply],
    });
    await store.fetchPending();
  });

  it('fetchPending populates the camelized pending replies', () => {
    expect(ScanSoloQuoteRepliesAPI.getPending).toHaveBeenCalledTimes(1);
    expect(store.replies.map(reply => reply.id)).toEqual([11, 12]);
    expect(store.replies[1]).toMatchObject({
      senderEmail: 'luciano@scansolo.com.br',
      kind: 'late_reply',
      quoteRequestId: 3,
    });
    expect(store.uiFlags.fetchingList).toBe(false);
  });

  it('link removes the reply once the server links it', async () => {
    ScanSoloQuoteRepliesAPI.link.mockResolvedValue({
      data: { quote_request_id: 7, status: 'replied' },
    });

    const result = await store.link(11, 7);

    expect(ScanSoloQuoteRepliesAPI.link).toHaveBeenCalledWith(11, 7);
    expect(result).toEqual({ quoteRequestId: 7, status: 'replied' });
    expect(store.replies.map(reply => reply.id)).toEqual([12]);
  });

  it('discard removes the reply once the server discards it', async () => {
    ScanSoloQuoteRepliesAPI.discard.mockResolvedValue({
      data: { id: 12, status: 'discarded' },
    });

    await store.discard(12);

    expect(ScanSoloQuoteRepliesAPI.discard).toHaveBeenCalledWith(12);
    expect(store.replies.map(reply => reply.id)).toEqual([11]);
  });

  it('keeps the reply and propagates the error on a 422', async () => {
    const error = {
      response: { status: 422, data: { error: 'quote_request_closed' } },
    };
    ScanSoloQuoteRepliesAPI.link.mockRejectedValue(error);

    await expect(store.link(12, 3)).rejects.toBe(error);
    expect(store.replies.map(reply => reply.id)).toEqual([11, 12]);
  });
});

describe('ScanSoloQuoteRepliesAPI', () => {
  const originalAxios = window.axios;
  const axiosMock = {
    get: vi.fn(() => Promise.resolve()),
    post: vi.fn(() => Promise.resolve()),
  };
  let api;

  beforeEach(async () => {
    window.axios = axiosMock;
    vi.clearAllMocks();
    ({ default: api } = await vi.importActual(
      'dashboard/api/scansoloQuoteReplies'
    ));
  });

  afterEach(() => {
    window.axios = originalAxios;
  });

  it('getPending lists only pending replies (CT-08)', () => {
    api.getPending();
    expect(axiosMock.get).toHaveBeenCalledWith(api.url, {
      params: { status: 'pending' },
    });
    expect(api.url).toMatch(/\/scan_solo\/quote_replies$/);
  });

  it('link posts the chosen quote request', () => {
    api.link(11, 7);
    expect(axiosMock.post).toHaveBeenCalledWith(`${api.url}/11/link`, {
      quote_request_id: 7,
    });
  });

  it('discard posts without a body', () => {
    api.discard(12);
    expect(axiosMock.post).toHaveBeenCalledWith(`${api.url}/12/discard`);
  });
});
