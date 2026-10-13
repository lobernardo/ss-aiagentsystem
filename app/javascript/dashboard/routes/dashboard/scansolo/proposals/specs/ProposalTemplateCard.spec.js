import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import ScanSoloProposalTemplateAPI from 'dashboard/api/scansoloProposalTemplate';
import ProposalTemplateCard from '../ProposalTemplateCard.vue';

vi.mock('dashboard/api/scansoloProposalTemplate', () => ({
  default: { show: vi.fn(), upload: vi.fn() },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

withFullI18n();
enableAutoUnmount(afterEach);

const SHA256 = 'abcdef0123456789'.repeat(4);

const template = {
  id: 3,
  filename: 'proposta-v3.docx',
  byte_size: 2048,
  sha256: SHA256,
  uploaded_by: { id: 1, name: 'Ana Admin' },
  uploaded_at: '2026-10-13T12:00:00Z',
};

const mountCard = ({ role = 'administrator' } = {}) =>
  mount(ProposalTemplateCard, {
    global: {
      plugins: [
        createStore({
          getters: {
            getCurrentRole: () => role,
            getCurrentUser: () => ({ id: 1 }),
            'accounts/isRTL': () => false,
          },
        }),
      ],
    },
  });

const selectFile = async wrapper => {
  const file = new File(['PK'], 'novo.docx');
  const input = wrapper.find('[data-testid="proposal-template-file"]');
  Object.defineProperty(input.element, 'files', { value: [file] });
  await input.trigger('change');
  return file;
};

describe('ProposalTemplateCard', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    ScanSoloProposalTemplateAPI.show.mockResolvedValue({ data: { template } });
  });

  it('shows the active template metadata with the 12-character hash prefix', async () => {
    const wrapper = mountCard();
    await flushPromises();

    expect(
      wrapper.find('[data-testid="proposal-template-filename"]').text()
    ).toBe('proposta-v3.docx');
    expect(
      wrapper.find('[data-testid="proposal-template-uploaded-by"]').text()
    ).toContain('Ana Admin');
    expect(
      wrapper.find('[data-testid="proposal-template-uploaded-at"]').text()
    ).toContain('13/10/2026');
    const hash = wrapper.find('[data-testid="proposal-template-sha256"]');
    expect(hash.text()).toContain(SHA256.slice(0, 12));
    expect(hash.text()).not.toContain(SHA256.slice(0, 13));
  });

  it('shows "Nenhum template ativo" without a template', async () => {
    ScanSoloProposalTemplateAPI.show.mockResolvedValue({
      data: { template: null },
    });
    const wrapper = mountCard();
    await flushPromises();

    expect(wrapper.find('[data-testid="proposal-template-none"]').text()).toBe(
      'Nenhum template ativo'
    );
  });

  it('shows the card without a file selector to an agent', async () => {
    const wrapper = mountCard({ role: 'agent' });
    await flushPromises();

    expect(
      wrapper.find('[data-testid="proposal-template-card"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="proposal-template-file"]').exists()
    ).toBe(false);
    expect(
      wrapper.find('[data-testid="proposal-template-upload"]').exists()
    ).toBe(false);
  });

  it('uploads the file as multipart `file`, refreshes the card and emits uploaded', async () => {
    const uploaded = { ...template, id: 4, filename: 'novo.docx' };
    ScanSoloProposalTemplateAPI.upload.mockResolvedValue({
      data: { template: uploaded },
    });
    const wrapper = mountCard();
    await flushPromises();

    const file = await selectFile(wrapper);
    await wrapper
      .find('[data-testid="proposal-template-upload-form"]')
      .trigger('submit');
    await flushPromises();

    expect(ScanSoloProposalTemplateAPI.upload).toHaveBeenCalledTimes(1);
    const payload = ScanSoloProposalTemplateAPI.upload.mock.calls[0][0];
    expect(payload).toBeInstanceOf(FormData);
    expect(payload.get('file')).toBe(file);
    expect(
      wrapper.find('[data-testid="proposal-template-filename"]').text()
    ).toBe('novo.docx');
    expect(useAlert).toHaveBeenCalledWith('Template da proposta atualizado.');
    expect(wrapper.emitted('uploaded')).toHaveLength(1);
  });

  it('alerts the i18n message with the placeholder names on a 422', async () => {
    ScanSoloProposalTemplateAPI.upload.mockRejectedValue({
      response: {
        status: 422,
        data: {
          error: 'missing_placeholders',
          placeholders: ['VALOR_EXTENSO'],
        },
      },
    });
    const wrapper = mountCard();
    await flushPromises();

    await selectFile(wrapper);
    await wrapper
      .find('[data-testid="proposal-template-upload-form"]')
      .trigger('submit');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'Faltam campos obrigatórios no template: VALOR_EXTENSO'
    );
    expect(wrapper.emitted('uploaded')).toBeUndefined();
    expect(
      wrapper.find('[data-testid="proposal-template-filename"]').text()
    ).toBe('proposta-v3.docx');
  });
});
