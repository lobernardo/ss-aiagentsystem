import { mount } from '@vue/test-utils';
import { createStore } from 'vuex';
import { withFullI18n } from 'test-i18n';
import TechnicalDetails from '../TechnicalDetails.vue';
import ScanSoloListState from '../ScanSoloListState.vue';
import ScanSoloTime from '../ScanSoloTime.vue';

withFullI18n();

const CORRELATION_ID = '6f1c2a0e-4b7d-4e1a-9c3f-2d8e5b7a1c90';

const storeFor = role =>
  createStore({
    getters: {
      getCurrentRole: () => role,
      getCurrentUser: () => ({ id: 5 }),
    },
  });

const mountDetails = role =>
  mount(TechnicalDetails, {
    props: {
      items: [
        { label: 'Correlation id', value: CORRELATION_ID },
        { label: 'Contexto', value: { history: ['oi'] } },
      ],
    },
    global: { plugins: [storeFor(role)] },
  });

describe('TechnicalDetails', () => {
  it('renders nothing for agents', () => {
    const wrapper = mountDetails('agent');

    expect(wrapper.find('[data-testid="technical-details"]').exists()).toBe(
      false
    );
    expect(wrapper.html()).not.toContain(CORRELATION_ID);
  });

  it('renders a collapsed block with the identifiers for administrators', () => {
    const wrapper = mountDetails('administrator');
    const details = wrapper.find('[data-testid="technical-details"]');

    expect(details.exists()).toBe(true);
    expect(details.element.tagName).toBe('DETAILS');
    expect(details.attributes('open')).toBeUndefined();
    expect(details.find('summary').text()).toBe('Detalhes técnicos');
    expect(details.text()).toContain(CORRELATION_ID);
    expect(details.find('pre').text()).toContain('"history"');
  });
});

describe('ScanSoloListState', () => {
  const mountState = props =>
    mount(ScanSoloListState, {
      props,
      slots: { default: '<p data-testid="content">itens</p>' },
    });

  it('shows the loading state first', () => {
    const wrapper = mountState({ loading: true, error: true, empty: true });

    expect(wrapper.find('[data-testid="list-state-loading"]').text()).toContain(
      'Carregando'
    );
    expect(wrapper.find('[data-testid="content"]').exists()).toBe(false);
  });

  it('shows the error state with a retry action', async () => {
    const wrapper = mountState({ error: true });

    expect(wrapper.find('[data-testid="list-state-error"]').text()).toContain(
      'Não foi possível carregar os dados.'
    );
    await wrapper.find('[data-testid="list-state-retry"]').trigger('click');
    expect(wrapper.emitted('retry')).toHaveLength(1);
  });

  it('shows the empty message, then the content', () => {
    expect(
      mountState({ empty: true, emptyMessage: 'Vazio' })
        .find('[data-testid="list-state-empty"]')
        .text()
    ).toBe('Vazio');
    expect(mountState({}).find('[data-testid="content"]').exists()).toBe(true);
  });
});

describe('ScanSoloTime', () => {
  it('renders relative text with the absolute value on hover and no ISO string', () => {
    const iso = '2026-01-05T12:00:00Z';
    const wrapper = mount(ScanSoloTime, { props: { value: iso } });
    const time = wrapper.find('[data-testid="scansolo-time"]');

    expect(time.text()).toMatch(/ago|in /);
    expect(time.attributes('title')).toBe('05/01/2026 12:00');
    expect(wrapper.html()).not.toContain('2026-01-05T');
  });

  it('renders the fallback without a value', () => {
    expect(
      mount(ScanSoloTime, { props: { value: null, fallback: '—' } }).text()
    ).toBe('—');
  });
});
