import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { SCANSOLO_MODULES } from './scansoloModules';
import ScanSoloComingSoonPage from './pages/ScanSoloComingSoonPage.vue';

const meta = {
  permissions: ['administrator', 'agent', 'custom_role'],
};

export default {
  routes: SCANSOLO_MODULES.map(scanSoloModule => ({
    path: frontendURL(`accounts/:accountId/scansolo/${scanSoloModule.path}`),
    name: scanSoloModule.name,
    meta,
    component: ScanSoloComingSoonPage,
    props: { moduleKey: scanSoloModule.key },
  })),
};
