import { setActivePinia, createPinia } from 'pinia';
import enMessages from 'dashboard/i18n/locale/en';
import ScanSoloProposalsAPI from 'dashboard/api/scansoloProposals';
import {
  PROPOSAL_ACTION_ERROR_LABELS,
  PROPOSAL_STATUS_LABELS,
  REASON_LABELS,
} from 'dashboard/routes/dashboard/scansolo/scansoloLabels';
import { useScansoloProposalsStore } from '../proposals';

vi.mock('dashboard/api/scansoloProposals', () => ({
  default: {
    get: vi.fn(),
    approve: vi.fn(),
    reject: vi.fn(),
  },
}));

const text = key =>
  key.split('.').reduce((node, part) => node?.[part], enMessages);

const awaitingVersion = {
  id: 11,
  version_number: 1,
  status: 'awaiting_approval',
  is_current: true,
  rejection_reason: null,
};

const proposal = {
  id: 5,
  opportunity_id: 3,
  current_version_id: 11,
  lead_email_present: true,
  versions: [awaitingVersion],
};

describe('useScansoloProposalsStore approval actions', () => {
  let store;

  beforeEach(async () => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    store = useScansoloProposalsStore();
    ScanSoloProposalsAPI.get.mockResolvedValue({ data: [proposal] });
    await store.fetchProposals();
  });

  it('rejects with the reason and updates the version (CT-03)', async () => {
    ScanSoloProposalsAPI.reject.mockResolvedValue({
      data: {
        ...awaitingVersion,
        status: 'rejected',
        rejection_reason: 'Valor errado',
      },
    });

    const version = await store.rejectProposal(5, 11, 'Valor errado');

    expect(ScanSoloProposalsAPI.reject).toHaveBeenCalledWith(
      5,
      11,
      'Valor errado'
    );
    expect(version).toMatchObject({
      status: 'rejected',
      rejectionReason: 'Valor errado',
    });
    expect(store.proposals[0].versions).toHaveLength(1);
    expect(store.proposals[0].versions[0]).toMatchObject({
      id: 11,
      status: 'rejected',
      rejectionReason: 'Valor errado',
    });
  });

  it('propagates a 422 and keeps the version untouched', async () => {
    const error = {
      response: { status: 422, data: { error: 'reason_required' } },
    };
    ScanSoloProposalsAPI.reject.mockRejectedValue(error);

    await expect(store.rejectProposal(5, 11, '')).rejects.toBe(error);
    expect(store.proposals[0].versions[0].status).toBe('awaiting_approval');
  });

  it('approves and updates the version (CT-02)', async () => {
    ScanSoloProposalsAPI.approve.mockResolvedValue({
      data: { ...awaitingVersion, status: 'approved' },
    });

    await store.approveProposal(5, 11, 'corr-1');

    expect(ScanSoloProposalsAPI.approve).toHaveBeenCalledWith(5, 11, 'corr-1');
    expect(store.proposals[0].versions[0].status).toBe('approved');
  });
});

describe('ScanSoloProposalsAPI#reject (CT-03)', () => {
  const originalAxios = window.axios;
  const axiosMock = { post: vi.fn(() => Promise.resolve()) };

  afterEach(() => {
    window.axios = originalAxios;
  });

  it('posts { proposal_version_id, reason } to .../proposals/:id/reject', async () => {
    window.axios = axiosMock;
    const { default: api } = await vi.importActual(
      'dashboard/api/scansoloProposals'
    );

    api.reject(5, 11, 'Valor errado');

    expect(axiosMock.post).toHaveBeenCalledWith(`${api.url}/5/reject`, {
      proposal_version_id: 11,
      reason: 'Valor errado',
    });
    expect(axiosMock.post.mock.calls[0][0]).toMatch(
      /\/scan_solo\/proposals\/5\/reject$/
    );
  });
});

describe('proposal labels', () => {
  it('labels the new version statuses (UI-01)', () => {
    expect(text(PROPOSAL_STATUS_LABELS.awaiting_approval)).toBe(
      'Aguardando aprovação'
    );
    expect(text(PROPOSAL_STATUS_LABELS.rejected)).toBe('Rejeitada');
  });

  it('labels every new failure reason', () => {
    [
      'lead_email_missing',
      'email_delivery_failed',
      'artifact_download_failed',
      'artifact_checksum_mismatch',
    ].forEach(reason => {
      expect(typeof text(REASON_LABELS[reason])).toBe('string');
    });
  });

  it('labels every approve/reject 422 code (CT-02, CT-03)', () => {
    [
      'not_awaiting_approval',
      'not_current_version',
      'lead_email_missing',
      'reason_required',
    ].forEach(code => {
      expect(typeof text(PROPOSAL_ACTION_ERROR_LABELS[code])).toBe('string');
    });
  });
});
