import { SCANSOLO_MODULES } from './scansoloModules';

// Pure helper so the ScanSolo sidebar entries can be unit tested without
// mounting the full (high-traffic, shared) Sidebar.vue component.
export const buildScanSoloSidebarItems = ({ t, accountScopedRoute }) =>
  SCANSOLO_MODULES.map(scanSoloModule => ({
    name: `ScanSolo ${scanSoloModule.key}`,
    label: t(`SCANSOLO.SIDEBAR.${scanSoloModule.key.toUpperCase()}`),
    icon: scanSoloModule.icon,
    to: accountScopedRoute(scanSoloModule.name),
    activeOn: [scanSoloModule.name],
  }));
