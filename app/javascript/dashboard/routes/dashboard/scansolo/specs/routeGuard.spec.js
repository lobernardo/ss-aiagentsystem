import { mount, flushPromises } from '@vue/test-utils';
import { createRouter, createMemoryHistory, RouterView } from 'vue-router';
import store from 'dashboard/store';
import scansoloRoutes from '../index';

vi.mock('dashboard/store', () => ({
  default: { getters: { 'accounts/getAccount': vi.fn() }, dispatch: vi.fn() },
}));

const buildRouter = () =>
  createRouter({
    history: createMemoryHistory(),
    routes: [
      {
        path: '/app/accounts/:accountId/dashboard',
        name: 'home',
        component: { template: '<div data-testid="home" />' },
      },
      ...scansoloRoutes.routes,
    ],
  });

const scanSoloPaths = [
  '/app/accounts/1/scansolo/agent',
  '/app/accounts/1/scansolo/pipeline',
  '/app/accounts/1/scansolo/pipeline/7',
  '/app/accounts/1/scansolo/agent/turns',
];

describe('ScanSolo route guard', () => {
  beforeEach(() => {
    window.axios = { get: vi.fn(), post: vi.fn(), put: vi.fn() };
  });

  it('guards every ScanSolo route', () => {
    scansoloRoutes.routes.forEach(route => {
      expect(route.beforeEnter).toBeDefined();
    });
  });

  it.each(scanSoloPaths)(
    'redirects %s to the dashboard when the flag is off, without ScanSolo API calls',
    async path => {
      store.getters['accounts/getAccount'].mockReturnValue({
        id: 1,
        scansolo_enabled: false,
      });
      const router = buildRouter();
      const wrapper = mount(RouterView, { global: { plugins: [router] } });

      await router.push(path);
      await flushPromises();

      expect(router.currentRoute.value.name).toBe('home');
      expect(router.currentRoute.value.params.accountId).toBe('1');
      expect(wrapper.find('[data-testid="home"]').exists()).toBe(true);
      expect(window.axios.get).not.toHaveBeenCalled();
      expect(window.axios.post).not.toHaveBeenCalled();
      expect(window.axios.put).not.toHaveBeenCalled();
    }
  );

  it('enters the ScanSolo route when the flag is on', async () => {
    store.getters['accounts/getAccount'].mockReturnValue({
      id: 1,
      scansolo_enabled: true,
    });
    const router = buildRouter();

    await router.push('/app/accounts/1/scansolo/agent');

    expect(router.currentRoute.value.name).toBe('scansolo_agent_index');
    expect(store.dispatch).not.toHaveBeenCalled();
  });

  it('loads the account first on a direct page load', async () => {
    store.getters['accounts/getAccount']
      .mockReturnValueOnce({})
      .mockReturnValue({ id: 1, scansolo_enabled: true });
    const router = buildRouter();

    await router.push('/app/accounts/1/scansolo/agent');

    expect(store.dispatch).toHaveBeenCalledWith('accounts/get', {
      silent: true,
      accountId: 1,
    });
    expect(router.currentRoute.value.name).toBe('scansolo_agent_index');
  });
});
