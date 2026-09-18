import { frontendURL } from 'dashboard/helper/URLHelper.js';
import { SCANSOLO_MODULES } from './scansoloModules';
import ScanSoloComingSoonPage from './pages/ScanSoloComingSoonPage.vue';
import KanbanBoard from './pipeline/KanbanBoard.vue';
import OpportunityDetail from './pipeline/OpportunityDetail.vue';
import AgentCenter from './agent/AgentCenter.vue';
import TurnEvidenceViewer from './agent/TurnEvidenceViewer.vue';
import KnowledgeCenter from './knowledge/KnowledgeCenter.vue';
import FollowUps from './followups/FollowUps.vue';
import Proposals from './proposals/Proposals.vue';
import Executions from './executions/Executions.vue';

const meta = {
  permissions: ['administrator', 'agent', 'custom_role'],
};

// Modules whose real screen has landed replace the ScanSoloComingSoonPage
// placeholder here; the rest fall back to it until their own phase lands.
const MODULE_COMPONENTS = {
  pipeline: KanbanBoard,
  agent: AgentCenter,
  knowledge: KnowledgeCenter,
  followups: FollowUps,
  proposals: Proposals,
  executions: Executions,
};

export default {
  routes: [
    ...SCANSOLO_MODULES.map(scanSoloModule => {
      const component = MODULE_COMPONENTS[scanSoloModule.key];

      return {
        path: frontendURL(
          `accounts/:accountId/scansolo/${scanSoloModule.path}`
        ),
        name: scanSoloModule.name,
        meta,
        component: component || ScanSoloComingSoonPage,
        ...(component ? {} : { props: { moduleKey: scanSoloModule.key } }),
      };
    }),
    {
      path: frontendURL('accounts/:accountId/scansolo/pipeline/:opportunityId'),
      name: 'scansolo_pipeline_opportunity_detail',
      meta,
      component: OpportunityDetail,
    },
    {
      path: frontendURL('accounts/:accountId/scansolo/agent/turns'),
      name: 'scansolo_agent_turn_evidence',
      meta,
      component: TurnEvidenceViewer,
    },
  ],
};
