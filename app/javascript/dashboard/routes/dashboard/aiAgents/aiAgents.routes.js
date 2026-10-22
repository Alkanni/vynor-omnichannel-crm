import { frontendURL } from '../../../helper/URLHelper';
import AiAgentsIndexPage from './pages/AiAgentsIndexPage.vue';
import AiAgentDetailPage from './pages/AiAgentDetailPage.vue';
import AiAgentGeneralPage from './pages/AiAgentGeneralPage.vue';

const meta = {
  permissions: ['administrator'],
};

export const routes = [
  {
    path: frontendURL('accounts/:accountId/ai-agents'),
    name: 'ai_agents_index',
    component: AiAgentsIndexPage,
    meta,
  },
  {
    path: frontendURL('accounts/:accountId/ai-agents/:agentId'),
    component: AiAgentDetailPage,
    meta,
    children: [
      {
        path: '',
        name: 'ai_agents_show',
        meta,
        redirect: to => ({ name: 'ai_agents_general', params: to.params }),
      },
      {
        path: 'general',
        name: 'ai_agents_general',
        component: AiAgentGeneralPage,
        meta,
      },
    ],
  },
];
