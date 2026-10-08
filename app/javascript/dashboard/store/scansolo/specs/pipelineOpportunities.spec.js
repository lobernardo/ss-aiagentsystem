import { setActivePinia, createPinia } from 'pinia';
import enMessages from 'dashboard/i18n/locale/en';
import ScanSoloPipelineOpportunitiesAPI from 'dashboard/api/scansoloPipelineOpportunities';
import {
  commercialStatusKey,
  FIELD_STATUS_LABELS,
  LEAD_EMAIL_ERROR_LABELS,
  LEAD_SOURCE_LABELS,
  LEAD_SOURCE_TAGS,
  TEMPLATE_SLOT_LABELS,
} from 'dashboard/routes/dashboard/scansolo/scansoloLabels';
import { MS_PER_DAY } from 'dashboard/routes/dashboard/scansolo/pipeline/pipelineConstants';
import { useScansoloPipelineOpportunitiesStore } from '../pipelineOpportunities';

vi.mock('dashboard/api/scansoloPipelineOpportunities', () => ({
  default: {
    get: vi.fn(),
    create: vi.fn(),
    stageTransition: vi.fn(),
    updateLeadEmail: vi.fn(),
  },
}));

const text = key =>
  key.split('.').reduce((node, part) => node?.[part], enMessages);

const existingOpportunity = {
  id: 1,
  stage: 'em_contato',
  contact_name: 'Ana',
  lead_source: 'website',
};

const manualLead = {
  id: 2,
  stage: 'novo_lead',
  contact_name: 'Bruno',
  lead_source: 'manual',
  company: 'Fazenda Boa Vista',
  quote_request_status: null,
  proposal_status: null,
  ai_control_state: 'ai_active',
  initial_template_failure: null,
  quote_request_resend_available: false,
  contact_created: true,
};

describe('useScansoloPipelineOpportunitiesStore#createOpportunity', () => {
  let store;

  beforeEach(async () => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    store = useScansoloPipelineOpportunitiesStore();
    ScanSoloPipelineOpportunitiesAPI.get.mockResolvedValue({
      data: [existingOpportunity],
    });
    await store.fetchOpportunities();
  });

  it('posts the payload and inserts the card in "Novo Lead"', async () => {
    const payload = { name: 'Bruno', phone_number: '+5511999999999' };
    ScanSoloPipelineOpportunitiesAPI.create.mockResolvedValue({
      data: manualLead,
    });

    const created = await store.createOpportunity(payload);

    expect(ScanSoloPipelineOpportunitiesAPI.create).toHaveBeenCalledWith(
      payload
    );
    expect(created).toMatchObject({
      id: 2,
      leadSource: 'manual',
      contactCreated: true,
    });
    expect(store.opportunities).toHaveLength(2);
    expect(store.byStage('novo_lead').map(o => o.id)).toEqual([2]);
  });

  it('propagates a 422 and inserts no card', async () => {
    const error = {
      response: {
        status: 422,
        data: { error: 'opportunity_exists', opportunity_id: 1 },
      },
    };
    ScanSoloPipelineOpportunitiesAPI.create.mockRejectedValue(error);

    await expect(store.createOpportunity({ name: 'Ana' })).rejects.toBe(error);
    expect(store.opportunities.map(o => o.id)).toEqual([1]);
  });
});

describe('useScansoloPipelineOpportunitiesStore#updateLeadEmail (CT-09)', () => {
  let store;

  beforeEach(async () => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    store = useScansoloPipelineOpportunitiesStore();
    ScanSoloPipelineOpportunitiesAPI.get.mockResolvedValue({
      data: [{ ...existingOpportunity, lead_email: null }],
    });
    await store.fetchOpportunities();
  });

  it('patches the e-mail and updates the card', async () => {
    ScanSoloPipelineOpportunitiesAPI.updateLeadEmail.mockResolvedValue({
      data: { ...existingOpportunity, lead_email: 'ana@fazenda.com.br' },
    });

    const updated = await store.updateLeadEmail(1, 'ana@fazenda.com.br');

    expect(
      ScanSoloPipelineOpportunitiesAPI.updateLeadEmail
    ).toHaveBeenCalledWith(1, 'ana@fazenda.com.br');
    expect(updated.leadEmail).toBe('ana@fazenda.com.br');
    expect(store.opportunities[0].leadEmail).toBe('ana@fazenda.com.br');
  });

  it('propagates a 422 and keeps the e-mail', async () => {
    const error = {
      response: { status: 422, data: { error: 'invalid_email' } },
    };
    ScanSoloPipelineOpportunitiesAPI.updateLeadEmail.mockRejectedValue(error);

    await expect(store.updateLeadEmail(1, 'ana@')).rejects.toBe(error);
    expect(store.opportunities[0].leadEmail).toBeNull();
  });
});

describe('ScanSoloPipelineOpportunitiesAPI#updateLeadEmail (CT-09)', () => {
  const originalAxios = window.axios;
  const axiosMock = { patch: vi.fn(() => Promise.resolve()) };

  afterEach(() => {
    window.axios = originalAxios;
  });

  it('patches .../pipeline_opportunities/:id with { email }', async () => {
    window.axios = axiosMock;
    const { default: api } = await vi.importActual(
      'dashboard/api/scansoloPipelineOpportunities'
    );

    api.updateLeadEmail(7, 'ana@fazenda.com.br');

    expect(axiosMock.patch).toHaveBeenCalledWith(`${api.url}/7`, {
      email: 'ana@fazenda.com.br',
    });
    expect(axiosMock.patch.mock.calls[0][0]).toMatch(
      /\/scan_solo\/pipeline_opportunities\/7$/
    );
  });
});

describe('ScanSoloPipelineOpportunitiesAPI#resendQuoteRequest (CT-12)', () => {
  const originalAxios = window.axios;
  const axiosMock = { post: vi.fn(() => Promise.resolve()) };

  afterEach(() => {
    window.axios = originalAxios;
  });

  it('posts to .../pipeline_opportunities/:id/quote_request/resend', async () => {
    window.axios = axiosMock;
    const { default: api } = await vi.importActual(
      'dashboard/api/scansoloPipelineOpportunities'
    );

    api.resendQuoteRequest(7);

    expect(axiosMock.post).toHaveBeenCalledWith(
      `${api.url}/7/quote_request/resend`
    );
    expect(axiosMock.post.mock.calls[0][0]).toMatch(
      /\/scan_solo\/pipeline_opportunities\/7\/quote_request\/resend$/
    );
  });
});

describe('commercialStatusKey', () => {
  it.each`
    quoteRequestStatus        | proposalStatus         | label
    ${null}                   | ${'generating'}        | ${'Gerando proposta'}
    ${'replied'}              | ${'generated'}         | ${'Proposta gerada'}
    ${'replied'}              | ${'approved'}          | ${'Proposta gerada'}
    ${'replied'}              | ${'sent'}              | ${'Proposta enviada'}
    ${'replied'}              | ${'failed'}            | ${'Falha na proposta'}
    ${'replied'}              | ${'awaiting_approval'} | ${'Aguardando aprovação'}
    ${'replied'}              | ${'rejected'}          | ${'Proposta rejeitada'}
    ${'awaiting_reply'}       | ${null}                | ${'Aguardando orçamento'}
    ${'correction_requested'} | ${null}                | ${'Correção solicitada'}
    ${'replied'}              | ${null}                | ${'Orçamento recebido'}
  `(
    '$quoteRequestStatus / $proposalStatus → $label',
    ({ quoteRequestStatus, proposalStatus, label }) => {
      expect(
        text(commercialStatusKey(quoteRequestStatus, proposalStatus))
      ).toBe(label);
    }
  );

  it('never presents a generated proposal as sent (RF-33)', () => {
    ['generated', 'approved'].forEach(status => {
      expect(text(commercialStatusKey('replied', status))).not.toMatch(
        /enviada/i
      );
    });
  });

  it('returns null without quote request or proposal', () => {
    expect(commercialStatusKey(null, null)).toBeNull();
    expect(commercialStatusKey(undefined, undefined)).toBeNull();
  });
});

describe('display mappings', () => {
  it('maps the LeadState classification only for display (RF-45)', () => {
    expect(text(FIELD_STATUS_LABELS.confirmado)).toBe('Coletado');
    expect(text(FIELD_STATUS_LABELS.inferido)).toBe('A confirmar');
    expect(text(FIELD_STATUS_LABELS.faltante)).toBe('Faltante');
  });

  it('labels the lead origin (UI-02, UI-04)', () => {
    expect(text(LEAD_SOURCE_TAGS.website)).toBe('SITE');
    expect(text(LEAD_SOURCE_TAGS.manual)).toBe('COMERCIAL');
    expect(text(LEAD_SOURCE_LABELS.website)).toBe('Site/WhatsApp');
    expect(text(LEAD_SOURCE_LABELS.manual)).toBe('Comercial');
    expect(text(LEAD_SOURCE_LABELS.none)).toBe('Não informada');
  });

  it('labels the lead e-mail 422 codes (CT-09)', () => {
    expect(text(LEAD_EMAIL_ERROR_LABELS.invalid_email)).toBe(
      'Informe um e-mail válido.'
    );
    expect(typeof text(LEAD_EMAIL_ERROR_LABELS.contact_conflict)).toBe(
      'string'
    );
  });

  it('labels the proposta_aviso_email template slot', () => {
    expect(typeof text(TEMPLATE_SLOT_LABELS.proposta_aviso_email)).toBe(
      'string'
    );
  });

  it('exposes one day in milliseconds', () => {
    expect(MS_PER_DAY).toBe(86400000);
  });
});
