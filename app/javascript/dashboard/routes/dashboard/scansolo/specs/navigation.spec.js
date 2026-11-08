import scansoloRoutes from '../index';
import { SCANSOLO_MODULES } from '../scansoloModules';
import { buildScanSoloSidebarItems } from '../scansoloSidebarItems';
import ScanSoloComingSoonPage from '../pages/ScanSoloComingSoonPage.vue';
import Reports from '../reports/Reports.vue';

describe('ScanSolo dashboard navigation', () => {
  it('declares the 7 net-new ScanSolo modules, Relatórios last', () => {
    expect(SCANSOLO_MODULES).toHaveLength(7);
    expect(SCANSOLO_MODULES.at(-1)).toEqual({
      key: 'reports',
      path: 'reports',
      name: 'scansolo_reports_index',
      icon: 'i-lucide-bar-chart-3',
    });
  });

  it('resolves scansolo_reports_index to the Relatórios screen with the module guard', () => {
    const route = scansoloRoutes.routes.find(
      r => r.name === 'scansolo_reports_index'
    );
    const pipelineRoute = scansoloRoutes.routes.find(
      r => r.name === 'scansolo_pipeline_index'
    );

    expect(route.component).toBe(Reports);
    expect(route.component).not.toBe(ScanSoloComingSoonPage);
    expect(route.beforeEnter).toBe(pipelineRoute.beforeEnter);
    expect(route.meta).toEqual(pipelineRoute.meta);
  });

  it('registers one SPA route per new ScanSolo module', () => {
    // >= rather than exact: individual modules (e.g. pipeline's opportunity
    // detail view) may register their own additional nested routes here.
    expect(scansoloRoutes.routes.length).toBeGreaterThanOrEqual(
      SCANSOLO_MODULES.length
    );

    SCANSOLO_MODULES.forEach(scanSoloModule => {
      const route = scansoloRoutes.routes.find(
        r => r.name === scanSoloModule.name
      );

      expect(route).toBeDefined();
      expect(route.path).toContain(`/scansolo/${scanSoloModule.path}`);
      // A real component (not a redirect/external link) means Vue Router
      // handles the navigation client-side, without a full page reload.
      expect(route.component).toBeDefined();
    });
  });

  it('gives every ScanSolo route a unique name', () => {
    const names = scansoloRoutes.routes.map(route => route.name);

    expect(new Set(names).size).toBe(names.length);
  });

  it('builds sidebar entries that link to a real route for every module', () => {
    const t = key => key;
    const accountScopedRoute = name => ({ name, params: { accountId: 1 } });

    const items = buildScanSoloSidebarItems({ t, accountScopedRoute });

    expect(items).toHaveLength(SCANSOLO_MODULES.length);

    items.forEach((item, index) => {
      const scanSoloModule = SCANSOLO_MODULES[index];

      expect(item.to.name).toBe(scanSoloModule.name);
      expect(item.label).toBe(
        `SCANSOLO.SIDEBAR.${scanSoloModule.key.toUpperCase()}`
      );
      expect(
        scansoloRoutes.routes.some(route => route.name === item.to.name)
      ).toBe(true);
    });
  });
});
