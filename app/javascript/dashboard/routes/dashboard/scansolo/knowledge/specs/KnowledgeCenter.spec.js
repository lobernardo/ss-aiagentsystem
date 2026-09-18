import { mount, flushPromises } from '@vue/test-utils';
import { createPinia, setActivePinia } from 'pinia';
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

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
}));

const seededSource = {
  id: 7,
  source_type: 'faq',
  title: 'Horário de atendimento',
  content: 'Atendemos de segunda a sexta.',
  origin: 'manual',
  enabled: true,
  added_by_id: 1,
  chunks_count: 2,
  file_attached: false,
  created_at: '2026-01-01T09:00:00Z',
  updated_at: '2026-01-01T09:00:00Z',
};

const sourceRow = (wrapper, id) =>
  wrapper.find(`[data-testid="source-row"][data-source-id="${id}"]`);

describe('KnowledgeCenter', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    ScanSoloKnowledgeSourcesAPI.get.mockResolvedValue({ data: [seededSource] });
  });

  it('lists sources with their type, chunk count and enabled state', async () => {
    const wrapper = mount(KnowledgeCenter);
    await flushPromises();

    const row = sourceRow(wrapper, seededSource.id);
    expect(row.exists()).toBe(true);
    expect(row.find('[data-testid="source-title"]').text()).toBe(
      seededSource.title
    );
    expect(row.find('[data-testid="source-chunks-count"]').text()).toBe('2');
    expect(row.find('[data-testid="source-enabled-indicator"]').text()).toBe(
      'SCANSOLO.KNOWLEDGE_CENTER.ENABLED'
    );
  });

  it('adds a FAQ source through the form (RF-27)', async () => {
    ScanSoloKnowledgeSourcesAPI.create.mockResolvedValue({
      data: { ...seededSource, id: 8, title: 'Nova pergunta' },
    });

    const wrapper = mount(KnowledgeCenter);
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

    const wrapper = mount(KnowledgeCenter);
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

    const wrapper = mount(KnowledgeCenter);
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
    ).toBe('SCANSOLO.KNOWLEDGE_CENTER.DISABLED');
  });

  it('reindexes a source (RF-31)', async () => {
    ScanSoloKnowledgeSourcesAPI.reindex.mockResolvedValue({
      data: { ...seededSource, chunks_count: 5 },
    });

    const wrapper = mount(KnowledgeCenter);
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
        .find('[data-testid="source-chunks-count"]')
        .text()
    ).toBe('5');
  });

  it('deletes a source (RF-33)', async () => {
    ScanSoloKnowledgeSourcesAPI.delete.mockResolvedValue({});

    const wrapper = mount(KnowledgeCenter);
    await flushPromises();

    await sourceRow(wrapper, seededSource.id)
      .find('[data-testid="delete-source-button"]')
      .trigger('click');
    await flushPromises();

    expect(ScanSoloKnowledgeSourcesAPI.delete).toHaveBeenCalledWith(
      seededSource.id
    );
    expect(sourceRow(wrapper, seededSource.id).exists()).toBe(false);
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

    const wrapper = mount(KnowledgeCenter);
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
