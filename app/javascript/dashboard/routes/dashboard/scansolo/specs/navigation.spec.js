import scansoloRoutes from '../index';
import { SCANSOLO_MODULES } from '../scansoloModules';
import { buildScanSoloSidebarItems } from '../scansoloSidebarItems';

describe('ScanSolo dashboard navigation', () => {
  it('registers one SPA route per new ScanSolo module', () => {
    expect(scansoloRoutes.routes).toHaveLength(SCANSOLO_MODULES.length);

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
