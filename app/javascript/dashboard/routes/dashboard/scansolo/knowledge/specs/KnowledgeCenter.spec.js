import { mount, flushPromises } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import ScanSoloKnowledgeSourcesAPI from 'dashboard/api/scansoloKnowledgeSources';
import ScanSoloKnowledgeRetrievalTestsAPI from 'dashboard/api/scansoloKnowledgeRetrievalTests';
import KnowledgeCenter from '../KnowledgeCenter.vue';

vi.mock('dashboard/api/scansoloKnowledgeSources', () => ({
  default: {
    get: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    delete: vi.fn(),
    reindex: vi.fn(),
  },
}));

vi.mock('dashboard/api/scansoloKnowledgeRetrievalTests', () => ({
  default: {
    run: vi.fn(),
  },
}));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

withFullI18n();

const seededSource = {
  id: 7,
  source_type: 'faq',
  title: 'Horário de atendimento',
  content: 'Atendemos de segunda a sexta.',
  origin: 'manual',
  enabled: true,
  added_by_id: 1,
  chunk_count: 2,
  index_status: 'indexed',
  index_error: null,
  indexed_at: '2026-01-01T09:01:00Z',
  file_attached: false,
  created_at: '2026-01-01T09:00:00Z',
  updated_at: '2026-01-01T09:00:00Z',
};

const ISO_PATTERN = /\d{4}-\d{2}-\d{2}T/;

const mountKnowledgeCenter = ({ role = 'administrator' } = {}) =>
  mount(KnowledgeCenter, {
    global: {
      plugins: [
        createStore({
          getters: {
            getCurrentRole: () => role,
            getCurrentUser: () => ({ id: 1 }),
          },
        }),
      ],
    },
  });

const sourceRow = (wrapper, id) =>
  wrapper.find(`[data-testid="source-row"][data-source-id="${id}"]`);

describe('KnowledgeCenter', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    ScanSoloKnowledgeSourcesAPI.get.mockResolvedValue({ data: [seededSource] });
  });

  it('lists sources with their type, chunk count and enabled state', async () => {
    const wrapper = mountKnowledgeCenter();
    await flushPromises();

    const row = sourceRow(wrapper, seededSource.id);
    expect(row.exists()).toBe(true);
    expect(row.find('[data-testid="source-title"]').text()).toBe(
      seededSource.title
    );
    expect(row.find('[data-testid="source-chunk-count"]').text()).toBe('2');
    expect(row.find('[data-testid="source-enabled-indicator"]').text()).toBe(
      'Ativa'
    );
  });

  it('adds a FAQ source through the form (RF-27)', async () => {
    ScanSoloKnowledgeSourcesAPI.create.mockResolvedValue({
      data: { ...seededSource, id: 8, title: 'Nova pergunta' },
    });

    const wrapper = mountKnowledgeCenter();
    await flushPromises();

    await wrapper.find('[data-testid="field-title"]').setValue('Nova pergunta');
    await wrapper
      .find('[data-testid="field-content"]')
      .setValue('Resposta de teste');
    await wrapper.find('[data-testid="field-origin"]').setValue('manual');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(ScanSoloKnowledgeSourcesAPI.create).toHaveBeenCalledTimes(1);
    const payload = ScanSoloKnowledgeSourcesAPI.create.mock.calls[0][0];
    expect(payload).toBeInstanceOf(FormData);
    expect(payload.get('title')).toBe('Nova pergunta');
    expect(payload.get('content')).toBe('Resposta de teste');
    expect(
      wrapper.find('[data-testid="source-row"][data-source-id="8"]').exists()
    ).toBe(true);
  });

  it('uploads a document with an attached file (RF-90)', async () => {
    ScanSoloKnowledgeSourcesAPI.create.mockResolvedValue({
      data: {
        ...seededSource,
        id: 9,
        source_type: 'document',
        file_attached: true,
      },
    });

    const wrapper = mountKnowledgeCenter();
    await flushPromises();

    const file = new File(['conteudo'], 'doc.txt', { type: 'text/plain' });
    const input = wrapper.find('[data-testid="field-file"]');
    Object.defineProperty(input.element, 'files', { value: [file] });
    await input.trigger('change');

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    const payload = ScanSoloKnowledgeSourcesAPI.create.mock.calls[0][0];
    expect(payload.get('file')).toBeInstanceOf(File);
    expect(payload.get('file').name).toBe('doc.txt');
  });

  it('toggles a source between enabled and disabled (RF-30)', async () => {
    ScanSoloKnowledgeSourcesAPI.update.mockResolvedValue({
      data: { ...seededSource, enabled: false },
    });

    const wrapper = mountKnowledgeCenter();
    await flushPromises();

    await sourceRow(wrapper, seededSource.id)
      .find('[data-testid="toggle-enabled-button"]')
      .trigger('click');
    await flushPromises();

    expect(ScanSoloKnowledgeSourcesAPI.update).toHaveBeenCalledWith(
      seededSource.id,
      { enabled: false }
    );
    expect(
      sourceRow(wrapper, seededSource.id)
        .find('[data-testid="source-enabled-indicator"]')
        .text()
    ).toBe('Desativada');
  });

  it('reindexes a source (RF-31)', async () => {
    ScanSoloKnowledgeSourcesAPI.reindex.mockResolvedValue({
      data: { ...seededSource, chunk_count: 5 },
    });

    const wrapper = mountKnowledgeCenter();
    await flushPromises();

    await sourceRow(wrapper, seededSource.id)
      .find('[data-testid="reindex-button"]')
      .trigger('click');
    await flushPromises();

    expect(ScanSoloKnowledgeSourcesAPI.reindex).toHaveBeenCalledWith(
      seededSource.id
    );
    expect(
      sourceRow(wrapper, seededSource.id)
        .find('[data-testid="source-chunk-count"]')
        .text()
    ).toBe('5');
  });

  it('deletes a source only after confirmation (RF-33, UI-09)', async () => {
    ScanSoloKnowledgeSourcesAPI.delete.mockResolvedValue({});

    const wrapper = mountKnowledgeCenter();
    await flushPromises();

    await sourceRow(wrapper, seededSource.id)
      .find('[data-testid="delete-source-button"]')
      .trigger('click');
    await flushPromises();

    expect(ScanSoloKnowledgeSourcesAPI.delete).not.toHaveBeenCalled();
    expect(
      wrapper.find('[data-testid="confirm-dialog-message"]').text()
    ).toContain(seededSource.title);

    await wrapper
      .find('[data-testid="confirm-dialog-confirm"]')
      .trigger('click');
    await flushPromises();

    expect(ScanSoloKnowledgeSourcesAPI.delete).toHaveBeenCalledWith(
      seededSource.id
    );
    expect(sourceRow(wrapper, seededSource.id).exists()).toBe(false);
    expect(useAlert).toHaveBeenCalledWith('Fonte excluída.');
  });

  it('cancelling the delete confirmation never calls the API', async () => {
    const wrapper = mountKnowledgeCenter();
    await flushPromises();

    await sourceRow(wrapper, seededSource.id)
      .find('[data-testid="delete-source-button"]')
      .trigger('click');
    await wrapper
      .find('[data-testid="confirm-dialog-cancel"]')
      .trigger('click');

    expect(ScanSoloKnowledgeSourcesAPI.delete).not.toHaveBeenCalled();
    expect(wrapper.find('[data-testid="confirm-dialog"]').exists()).toBe(false);
  });

  describe('UI-11: indexing state', () => {
    const statusFixtures = [
      {
        ...seededSource,
        id: 1,
        index_status: 'pending',
        indexed_at: null,
        chunk_count: 0,
      },
      {
        ...seededSource,
        id: 2,
        index_status: 'indexing',
        indexed_at: null,
        chunk_count: 0,
      },
      { ...seededSource, id: 3, index_status: 'indexed', chunk_count: 4 },
      {
        ...seededSource,
        id: 4,
        index_status: 'failed',
        chunk_count: 0,
        indexed_at: null,
        index_error: 'Não foi possível extrair texto do arquivo.',
      },
    ];

    it('renders the badge of each status, the chunk count and the error for failed sources', async () => {
      ScanSoloKnowledgeSourcesAPI.get.mockResolvedValue({
        data: statusFixtures,
      });
      const wrapper = mountKnowledgeCenter();
      await flushPromises();

      const badge = id =>
        sourceRow(wrapper, id)
          .find('[data-testid="source-index-status"]')
          .text();
      expect([badge(1), badge(2), badge(3), badge(4)]).toEqual([
        'Na fila',
        'Indexando',
        'Indexada',
        'Falhou',
      ]);
      expect(
        sourceRow(wrapper, 4).find('[data-testid="source-index-error"]').text()
      ).toContain('Não foi possível extrair texto do arquivo.');
      expect(
        sourceRow(wrapper, 3)
          .find('[data-testid="source-index-error"]')
          .exists()
      ).toBe(false);
      expect(sourceRow(wrapper, 1).text()).toContain('Ainda não indexada');
      expect(
        sourceRow(wrapper, 3)
          .find('[data-testid="source-indexed-at"]')
          .attributes('title')
      ).toBe('01/01/2026 09:01');
    });
  });

  describe('UI-10: role-based rendering', () => {
    it('hides write controls, technical ids and ISO strings from agents', async () => {
      const wrapper = mountKnowledgeCenter({ role: 'agent' });
      await flushPromises();

      expect(wrapper.find('[data-testid="add-source-button"]').exists()).toBe(
        false
      );
      expect(
        wrapper.find('[data-testid="delete-source-button"]').exists()
      ).toBe(false);
      expect(wrapper.find('[data-testid="reindex-button"]').exists()).toBe(
        false
      );
      expect(
        wrapper.find('[data-testid="run-retrieval-button"]').exists()
      ).toBe(false);
      expect(wrapper.find('[data-testid="technical-details"]').exists()).toBe(
        false
      );
      expect(wrapper.html()).not.toMatch(ISO_PATTERN);
      expect(
        wrapper.find('[data-testid="knowledge-read-only-notice"]').exists()
      ).toBe(true);
    });

    it('shows technical ids to administrators inside the collapsed block', async () => {
      const wrapper = mountKnowledgeCenter();
      await flushPromises();

      const details = sourceRow(wrapper, seededSource.id).find(
        '[data-testid="technical-details"]'
      );
      expect(details.attributes('open')).toBeUndefined();
      expect(details.text()).toContain(String(seededSource.id));
      expect(details.text()).toMatch(ISO_PATTERN);
    });
  });

  describe('UI-09: loading, empty and error states', () => {
    it('renders the loading state', async () => {
      ScanSoloKnowledgeSourcesAPI.get.mockReturnValue(new Promise(() => {}));
      const wrapper = mountKnowledgeCenter();
      await flushPromises();

      expect(wrapper.find('[data-testid="list-state-loading"]').exists()).toBe(
        true
      );
    });

    it('renders the empty state', async () => {
      ScanSoloKnowledgeSourcesAPI.get.mockResolvedValue({ data: [] });
      const wrapper = mountKnowledgeCenter();
      await flushPromises();

      expect(wrapper.find('[data-testid="list-state-empty"]').text()).toBe(
        'Nenhuma fonte cadastrada ainda.'
      );
    });

    it('renders the error state and retries', async () => {
      ScanSoloKnowledgeSourcesAPI.get.mockRejectedValueOnce(new Error('boom'));
      const wrapper = mountKnowledgeCenter();
      await flushPromises();

      expect(wrapper.find('[data-testid="list-state-error"]').exists()).toBe(
        true
      );
      await wrapper.find('[data-testid="list-state-retry"]').trigger('click');
      await flushPromises();
      expect(sourceRow(wrapper, seededSource.id).exists()).toBe(true);
    });

    it('toasts the server message when a mutation fails', async () => {
      ScanSoloKnowledgeSourcesAPI.reindex.mockRejectedValue({
        response: { status: 429, data: { error: 'Retry later' } },
      });
      const wrapper = mountKnowledgeCenter();
      await flushPromises();

      await sourceRow(wrapper, seededSource.id)
        .find('[data-testid="reindex-button"]')
        .trigger('click');
      await flushPromises();

      expect(useAlert).toHaveBeenCalledWith('Retry later');
    });
  });

  it('runs the retrieval simulator and shows ranked results with evidence ids (RF-29, RF-32)', async () => {
    ScanSoloKnowledgeRetrievalTestsAPI.run.mockResolvedValue({
      data: {
        results: [
          {
            chunk_id: 1,
            source_id: 7,
            source_type: 'faq',
            content_snippet: 'Atendemos de segunda a sexta.',
            similarity_score: 0.87,
          },
        ],
        failure_reason: null,
      },
    });

    const wrapper = mountKnowledgeCenter();
    await flushPromises();

    await wrapper.find('[data-testid="field-query"]').setValue('horário');
    await wrapper.findAll('form').at(1).trigger('submit');
    await flushPromises();

    expect(ScanSoloKnowledgeRetrievalTestsAPI.run).toHaveBeenCalledWith(
      'horário',
      5
    );
    const result = wrapper.find('[data-testid="retrieval-result"]');
    expect(result.exists()).toBe(true);
    expect(result.find('[data-testid="retrieval-result-snippet"]').text()).toBe(
      'Atendemos de segunda a sexta.'
    );
  });
});
